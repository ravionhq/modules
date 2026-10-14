# Preview Ingress Module

This module creates the entry point for sandbox previews: an internet-facing Network Load Balancer with a Ravion-managed wildcard domain and certificate, in front of one preview router instance. The router forwards each preview hostname to the sandbox that serves it and wakes a paused sandbox when a request arrives for it.

Requests travel from the browser to the load balancer, to the router, to the sandbox host, all inside your AWS account. Ravion tells the router which hostname belongs to which sandbox over a connection the router opens outbound.

## What Terraform creates

| Resource | Purpose |
| --- | --- |
| Network Load Balancer | Internet-facing, cross-zone, with its own security group |
| TLS listener on 443 | Terminates TLS with the wildcard certificate and forwards to the router on TCP 8080 |
| TCP listener on 80 | Forwards to the router on TCP 8081, where plain HTTP is redirected to HTTPS |
| Two target groups | Instance targets with the client address preserved, health checked over HTTP on `/healthz`, port 8082 |
| Wildcard certificate and DNS record | `*.<name>.<apex>` on Ravion's managed apex, where the name is `ravion_domain_name` or, when that is unset, the module instance given id, issued through the `ravion_aws_acm_certificate` resource and pointed at the load balancer |
| Custom domain certificate and domains | One certificate for every entry of `domains`, attached to the TLS listener beside the wildcard certificate, and one `ravion_domain` per entry pointed at the load balancer. Created only with `domains` |
| Launch template and Auto Scaling group | One router instance, replaced when it turns unhealthy or when the launch template changes; the replacement is launched and healthy before the old instance is drained |
| Two security groups | One for the load balancer, one for the router |
| Sandbox host rules | One inbound rule on each of `sandbox_host_security_group_ids`: the preview port range from the router's group |
| IAM role and instance profile | Session Manager access for operators. Created only with `ssm_enabled` |

## Usage

Inside Ravion, create a module instance of `rvn-preview-ingress`. The stack run supplies `module_instance_id` and the provider credentials.

```hcl
module "preview_ingress" {
  source = "git::https://github.com/ravionhq/modules.git//networking/preview_ingress?ref=rvn-preview-ingress@0.1.0"

  name               = "previews"
  module_instance_id = "minst_..."
  ravion_domain_name = "previews"
  ravion_api_url     = "https://api.ravion.com"

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  router_subnet_ids = module.vpc.private_subnet_ids

  sandbox_host_security_group_ids = ["sg-0123456789abcdef0"]

  tags = {
    Environment = "staging"
  }
}
```

Serve previews under your own wildcard domain as well:

```hcl
module "preview_ingress" {
  source = "git::https://github.com/ravionhq/modules.git//networking/preview_ingress?ref=rvn-preview-ingress@0.1.0"

  name               = "previews"
  module_instance_id = "minst_..."
  ravion_domain_name = "previews"
  ravion_api_url     = "https://api.ravion.com"
  domains            = ["*.preview.example.com"]

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  router_subnet_ids = module.vpc.private_subnet_ids

  sandbox_host_security_group_ids = ["sg-0123456789abcdef0"]
}
```

Run the router in public subnets:

```hcl
module "preview_ingress" {
  source = "git::https://github.com/ravionhq/modules.git//networking/preview_ingress?ref=rvn-preview-ingress@0.1.0"

  name               = "previews"
  module_instance_id = "minst_..."
  ravion_domain_name = "previews"
  ravion_api_url     = "https://api.ravion.com"

  vpc_id                   = module.vpc.vpc_id
  public_subnet_ids        = module.vpc.public_subnet_ids
  router_subnet_ids        = module.vpc.public_subnet_ids
  router_public_ip_enabled = true

  sandbox_host_security_group_ids = ["sg-0123456789abcdef0"]
}
```

Inside a Ravion stack run the runner injects `module_instance_id`, `module_instance_given_id` and `ravion_api_url`. Outside a Ravion pipeline, set them as above and export `RAVION_BASE_URL` and `RAVION_API_KEY` for the `ravion` provider before applying.

## Custom domains

`domains` lists wildcard domains previews can be served under, beside the Ravion wildcard domain. Each entry is `*.<domain>` in a DNS zone you control, such as `*.preview.example.com`, and a preview takes one hostname below it, such as `feature-x.preview.example.com`. The list holds at most 10 entries.

The module creates one `ravion_aws_acm_certificate` with every entry as a name and the TLS listener as its target, and one `ravion_domain` per entry that points at the load balancer. Ravion attaches the certificate to the listener once it is issued. The wildcard certificate on Ravion's managed apex stays the listener's default certificate, and the load balancer picks the certificate by the hostname a client asks for.

Add two DNS records for each entry at your DNS provider: the certificate's validation record and the routing record that points the wildcard at the load balancer. Ravion provides both. An apply finishes without waiting for them. Previews under a custom domain answer after the certificate is issued and the routing record resolves.

Entries are lowercased and trimmed of whitespace and a trailing dot. An entry under Ravion's managed apex is refused: its records would belong to Ravion's DNS zone, which only Ravion can edit.

## The router instance

The instance boots an image that carries systemd and the preview router at `/usr/local/bin/preview-router`. Ravion publishes a preview router image with each router release, so by default that is the newest image the `image_owner` account publishes under `image_name_pattern` for the instance type's architecture. Set `image_id` to pin an image.

The boot script does three things, in order, and stops at the first one that fails:

1. Checks that the image's preview router runs, and logs its release.
2. Writes `/etc/ravion/preview-router.env` with the Ravion API origin and the module instance id.
3. Writes and starts `ravion-preview-router.service`, which runs `preview-router`.

The script holds no credential and logs none. The router obtains its credential from Ravion at start: it presents the instance's signed identity document, and Ravion checks that the instance runs in the module instance's AWS account and carries the tag `ravion:preview-router = <module_instance_id>`. The module sets that tag on the instance. The credential stays in the router's memory.

An instance whose boot script fails never starts the router. It stays unhealthy behind the load balancer, the Auto Scaling group replaces it after the health check grace period, and the apply that launched it fails after ten minutes without a healthy router. The reason is in the instance's console output and in `/var/log/cloud-init-output.log`, on the line that starts with `preview router setup: FAILED`.

The router runs the release its image carries. A change to the launch template (image, instance type, API origin, tags) replaces the instance: the new router is launched first, receives its routes from Ravion and passes its health check, and only then is the old one drained and terminated. A newer image found by the lookup is such a change; pin `image_id` to decide when it happens.

A router answers its health check only once it holds its routes, and keeps answering it if it later loses its connection to Ravion: it goes on forwarding every running preview, and only waking a paused one waits for the connection. A router instance that fails its health checks is replaced by the Auto Scaling group.

## Security groups

| Group | Inbound | Outbound |
| --- | --- | --- |
| Load balancer | TCP 443 and 80 from `ingress_cidr_blocks` | TCP 8080, 8081 and 8082 to the router's group |
| Router | TCP 8080, 8081 and 8082 from the load balancer's group | TCP 443 to any address; TCP 20000-20998 to the VPC's IPv4 ranges |

No CIDR reaches the router. Its outbound HTTPS serves the Ravion API and AWS APIs. Ports 20000-20998 are where sandbox hosts publish previews, and the router can open no other connection inside the VPC. A Ravion API on a port other than 443 adds that port to the router's outbound rules.

The module adds one inbound rule to each security group in `sandbox_host_security_group_ids`: TCP 20000-20998 from the router's group. These are the groups of the sandbox hosts whose previews the router serves, and the router reaches no sandbox host outside them. The rules belong to this module, so a destroy removes them before the router's group. AWS refuses to delete a security group that another group's rule still names.

## Session Manager

`ssm_enabled` gives the instance a role with the `AmazonSSMManagedInstanceCore` policy and no other permission. Session Manager also needs the SSM Agent in the image. Turn `ssm_enabled` off to launch the instance with no IAM role.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |
| ravion (`providers.ravion.com/ravion/ravion`) | = 0.0.3-rc.1, configured from `RAVION_BASE_URL` / `RAVION_API_KEY` |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name of the load balancer and the prefix of every other resource (1-32 characters) | `string` | n/a | yes |
| module_instance_id | Ravion module instance id (`minst_*`) this preview ingress belongs to; the router's identity. Injected as `TF_VAR_module_instance_id` inside a stack run | `string` | n/a | yes |
| ravion_api_url | Origin of the Ravion API the router connects to. Injected as `TF_VAR_ravion_api_url` inside a stack run | `string` | n/a | yes |
| vpc_id | VPC of the load balancer, the router and the sandboxes it serves | `string` | n/a | yes |
| public_subnet_ids | Public subnets for the load balancer | `list(string)` | n/a | yes |
| router_subnet_ids | Subnets the router instance launches in, in Availability Zones the public subnets cover. The router needs outbound HTTPS | `list(string)` | n/a | yes |
| router_public_ip_enabled | Give the router instance a public IPv4 address, for public `router_subnet_ids` | `bool` | `false` | no |
| sandbox_host_security_group_ids | Security groups of the sandbox hosts whose previews the router serves. Each gets one inbound rule for the router's group on the preview port range | `list(string)` | `[]` | no |
| ingress_cidr_blocks | IPv4 CIDR blocks allowed to reach the load balancer on 443 and 80. An empty list allows none | `list(string)` | `["0.0.0.0/0"]` | no |
| ssl_policy | Security policy of the TLS listener | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| instance_type | EC2 instance type of the router | `string` | `"t3.small"` | no |
| image_id | AMI the router boots. Null looks up the newest image of `image_owner` | `string` | `null` | no |
| image_owner | AWS account that publishes the looked-up image: a 12-digit ID, or `self`, `amazon`, `aws-marketplace` | `string` | `"600013814144"` | no |
| image_name_pattern | AMI name pattern of the looked-up image | `string` | `"ravion-preview-router-*"` | no |
| ssm_enabled | Give the instance a role that allows Session Manager and nothing else | `bool` | `true` | no |
| ravion_domain_name | Name leaf of the wildcard domain: Ravion issues `*.<name>.<apex>`. Null uses the module instance given id | `string` | `null` | no |
| module_instance_given_id | The module instance's given id, the default leaf of the wildcard domain. Injected as `TF_VAR_module_instance_given_id` inside a stack run | `string` | `null` | no |
| domains | Custom wildcard domains previews can be served under, each `*.<domain>` in a DNS zone you control. At most 10 | `list(string)` | `[]` | no |
| ravion_aws_account_id | Ravion AWS account record id (`aws_*`) the certificate is issued in. Null detects it from the run's AWS credentials | `string` | `null` | no |
| region | AWS region. Null uses the provider's region | `string` | `null` | no |
| tags | Tags to assign to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| sandbox_router_id | The router's identity: the module instance id it enrolls with |
| sandbox_router_dns_name | DNS name of the load balancer in front of the router |
| sandbox_router_zone_id | Canonical hosted zone ID of the load balancer |
| sandbox_router_load_balancer_arn | ARN of the load balancer in front of the router |
| sandbox_router_security_group_id | ID of the router instance's security group |
| sandbox_host_security_group_ids | IDs of the sandbox host security groups that admit the router on the preview port range |
| wildcard_domain_name | The apex previews are served under |
| certificate_arn | ARN of the wildcard certificate on the TLS listener |
| custom_domain_names | The custom wildcard domains previews can be served under |
| custom_certificate_arn | ARN of the certificate that covers the custom domains. Null when there are none |
| load_balancer_security_group_id | ID of the load balancer's security group |
| autoscaling_group_name | Name of the Auto Scaling group that keeps the router running |
| image_id | The AMI new router instances boot |
| aws_account_id | AWS account ID where the resources are deployed |
| region | AWS region where the resources are deployed |

Ravion reads the `sandbox_router_*` outputs to route the previews of this module instance's wildcard domain through the router.

## Limits

- One router instance. A change to it is rolled out by launching the replacement first; an instance that fails is replaced by the Auto Scaling group once its health checks fail.
- IPv4 only, and an internet-facing load balancer only.
- HTTP/1.1 between the load balancer and the router. WebSocket upgrades pass through.
- The load balancer writes no access logs.

## Testing

```bash
tofu init -backend=false
tofu test
tests/user_data_test.sh
```

`tofu test` plans the module against mocked providers. `tests/user_data_test.sh` renders the boot script and runs it in a throwaway Debian container with a stand-in for systemctl: an image with its router, an image without one, and a router that cannot run. It needs Docker.
