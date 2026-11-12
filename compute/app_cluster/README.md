# App Cluster Module

This module creates the entry point of an App Cluster: an internet-facing Network Load Balancer with a Ravion-managed wildcard domain and certificate, and any custom wildcard domains, in front of a router that forwards each app hostname to its sandbox and wakes a paused app when a request arrives for it.

The apps run in sandboxes on the sandbox pool of an existing execution environment in the same VPC, chosen in the module definition, not in this Terraform. Ravion runs the router instance and the pool's hosts. This module creates what the router runs in: its security group, IAM role and instance profile, and the load balancer and its target groups. Requests travel from the browser to the load balancer, to the router, to the sandbox host, all inside your AWS account.

## What Terraform creates

| Resource | Purpose |
| --- | --- |
| Network Load Balancer | Internet-facing, cross-zone, with its own security group |
| TLS listener on 443 | Terminates TLS with the wildcard certificate and forwards to the router on TCP 8080 |
| TCP listener on 80 | Forwards to the router on TCP 8081, where plain HTTP is redirected to HTTPS |
| Two target groups | Instance targets with the client address preserved and a 30 second deregistration delay, health checked over HTTP on `/healthz`, port 8082. Ravion registers the router instance in both |
| Wildcard certificate and DNS record | `*.<name>.<apex>` on Ravion's managed apex, where the name is `ravion_domain_name` or, when that is unset, the module instance given id, issued through the `ravion_aws_acm_certificate` resource and pointed at the load balancer |
| Custom domain certificate and domains | One certificate for every entry of `domains`, attached to the TLS listener beside the wildcard certificate, and one `ravion_domain` per entry pointed at the load balancer. Created only with `domains` |
| Two security groups | One for the load balancer, one for the router |
| Router IAM role and instance profile | Lets the router publish its metrics to CloudWatch in the `Ravion/AppRouter` namespace. With `ssm_enabled`, also Session Manager access for operators. Ravion launches the router with the instance profile |

The module creates no sandbox pool, hosts or hosts' security group: those are the execution environment's. It creates no router instance, launch template or Auto Scaling group either. Ravion launches the router in `router_subnet_ids` with the router's security group and instance profile, registers it in both target groups once it holds its routes, and replaces it the same way: the new router is registered before the old one is drained and terminated.

## Usage

Inside Ravion, create a module instance of `rvn-aws-app-cluster`. The stack run supplies `module_instance_id`, `module_instance_given_id`, `ravion_api_url` and the provider credentials.

```hcl
module "app_cluster" {
  source = "git::https://github.com/ravionhq/modules.git//compute/app_cluster?ref=rvn-aws-app-cluster@0.1.0"

  name               = "apps"
  module_instance_id = "minst_..."
  ravion_domain_name = "apps"

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  router_subnet_ids = module.vpc.private_subnet_ids

  tags = {
    Environment = "staging"
  }
}
```

Serve the apps under custom wildcard domains as well:

```hcl
module "app_cluster" {
  source = "git::https://github.com/ravionhq/modules.git//compute/app_cluster?ref=rvn-aws-app-cluster@0.1.0"

  name               = "apps"
  module_instance_id = "minst_..."

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  router_subnet_ids = module.vpc.private_subnet_ids

  domains = ["*.apps.example.com"]
}
```

Outside a Ravion pipeline, set `module_instance_id` as above and export `RAVION_BASE_URL` and `RAVION_API_KEY` for the `ravion` provider before applying.

## The execution environment

The apps run on the sandbox pool of an existing execution environment, the module definition's `execution_environment_id` input. It must be an AWS execution environment in the module's AWS account, region and VPC, with a sandbox pool. The pool's settings (instance types, markets, warm hosts, max hosts) are the execution environment's. This Terraform does not read it: the module definition hands it to Ravion in the `apps` block.

## Custom domains

Each entry of `domains` is a wildcard, `*.<domain>`, in a DNS zone you control, at most 10 and each at most 191 characters without its `*.`. One certificate covers all of them and is attached to the TLS listener beside the wildcard certificate, which stays the listener's default; each entry also gets a `ravion_domain` that points it at the load balancer. Add the validation and routing records Ravion provides at your DNS provider. Every app is then also served one label below each entry: `<app>.<domain>` and `<app>-<port name>.<domain>`. Entries under Ravion's managed apex are refused.

An app's own domains, from its `ravion-app.yaml`, are not in this Terraform: Ravion requests their certificates on the TLS listener, `tls_listener_arn`, and points them at the load balancer.

## Security groups

| Group | Inbound | Outbound |
| --- | --- | --- |
| Load balancer | TCP 443 and 80 from `ingress_cidr_blocks` | TCP 8080, 8081 and 8082 to the router's group |
| Router | TCP 8080, 8081 and 8082 from the load balancer's group | TCP 443 to any address; TCP 20000-20999 to each IPv4 range of the VPC |

No CIDR reaches the router. The router's outbound HTTPS serves the Ravion API and AWS APIs; a Ravion API on a port other than 443 adds that port. Ports 20000-20999 are where sandbox hosts serve the apps' ports, the last one being the hosts' own health port, and the router can open no other connection inside the VPC. The VPC's ranges are read with the `aws_vpc` data source: the primary range and every range associated with it.

The hosts are the execution environment's, in its security group. While the router runs, Ravion adds the rule there that admits the router's group on TCP 20000-20999 (`ravion app router <module instance id>`), and removes it when the router stops. A destroy of the cluster stops the router first, so Terraform never deletes the router's group while a rule outside this stack names it. To let the apps reach a database or another service, allow the execution environment's security group in that resource's security group.

## Session Manager

`ssm_enabled` attaches the `AmazonSSMManagedInstanceCore` policy to the router's role. Turn it off to leave the role with only the permission to publish the router's metrics.

## Metrics

The router publishes request metrics, and the use of the instance it runs on, to CloudWatch every minute, in the `Ravion/AppRouter` namespace of the module's account and region. The router's role allows `cloudwatch:PutMetricData` with the condition `cloudwatch:namespace = Ravion/AppRouter`. The action has no resource-level permissions, so the namespace condition is its only scope.

Every datum carries the `Router` dimension, the cluster's module instance id, alone or with `App` (the app) or `Hostname`.

| Metric | Description |
| --- | --- |
| `Requests` | Requests |
| `Responses2xx`, `Responses3xx`, `Responses4xx`, `Responses5xx` | Responses by status class |
| `Latency` | Request latency in milliseconds, as a statistic set |
| `UnknownHostnameRequests` | Requests for a hostname with no route |
| `Wakes`, `WakeFailures` | Wakes of paused apps, and those that failed |
| `WakeDuration` | Wake duration in milliseconds, as a statistic set |
| `HeldRequests` | Requests held while their app wakes, the maximum in the minute |
| `OpenWebSockets` | Open WebSocket connections, the maximum in the minute |
| `Routes` | Routes the router holds |
| `ControlPlaneConnected` | 1 while the router is connected to Ravion, otherwise 0 |
| `MemoryUsedMiB` | Memory the router uses, in MiB |
| `RouterInstanceCPUUtilization` | Share of the minute the router instance's CPUs were busy, in percent |
| `RouterInstanceMemoryUtilization` | Share of the router instance's memory in use, in percent |
| `RouterInstanceNetworkInBytes`, `RouterInstanceNetworkOutBytes` | Bytes the router instance's network interfaces received and sent in the minute |

The router instance's metrics carry the `Router` dimension alone. While Ravion replaces the router, both instances publish under the same `Router`, so the charts show the higher of their CPU and memory shares (`Maximum`) and the sum of their bytes.

The module's definition charts these on the Metrics tab beside the load balancer's `AWS/NetworkELB` metrics and the execution environment's pool host minutes from the `BusyHosts` series its hosts publish in `Ravion/SandboxHost`.

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
| module_instance_id | Ravion module instance id (`minst_*`) of this App Cluster. Injected as `TF_VAR_module_instance_id` inside a stack run | `string` | n/a | yes |
| vpc_id | VPC of the load balancer and the router. The router reaches TCP 20000-20999 in each of its IPv4 ranges | `string` | n/a | yes |
| public_subnet_ids | Public subnets for the load balancer | `list(string)` | n/a | yes |
| router_subnet_ids | Subnets Ravion may launch the router in, in Availability Zones the public subnets cover. The router needs outbound HTTPS | `list(string)` | n/a | yes |
| ingress_cidr_blocks | IPv4 CIDR blocks allowed to reach the load balancer on 443 and 80. An empty list allows none | `list(string)` | `["0.0.0.0/0"]` | no |
| ssl_policy | Security policy of the TLS listener | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| ssm_enabled | Add Session Manager access to the router's role | `bool` | `true` | no |
| ravion_api_url | Origin of the Ravion API. A port other than 443 is added to the router's outbound rules. Injected as `TF_VAR_ravion_api_url` inside a stack run | `string` | `null` | no |
| ravion_domain_name | Name leaf of the wildcard domain: Ravion issues `*.<name>.<apex>`. Null uses the module instance given id | `string` | `null` | no |
| module_instance_given_id | The module instance's given id, the default leaf of the wildcard domain. Injected as `TF_VAR_module_instance_given_id` inside a stack run | `string` | `null` | no |
| domains | Custom wildcard domains attached to the load balancer, each `*.<domain>` in a DNS zone you control and at most 191 characters without its `*.`. Apps are also served one label below each. At most 10 | `list(string)` | `[]` | no |
| ravion_aws_account_id | Ravion AWS account record id the certificates are issued in. Null detects it from the run's AWS credentials | `string` | `null` | no |
| region | AWS region. Null uses the provider's region | `string` | `null` | no |
| tags | Tags to assign to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| wildcard_domain_name | The apex apps are served under, without `*.` |
| custom_domain_apexes | The custom wildcard domains without their `*.`, in the order given; apps are also served one label below each |
| tls_listener_arn | ARN of the TLS listener, where Ravion attaches the certificate of each app's own domains |
| router_subnet_ids | The subnets Ravion may launch the router in |
| router_security_group_id | ID of the router's security group |
| router_instance_profile_name | Name of the router's instance profile; its role has the same name |
| traffic_target_group_arn | ARN of the target group the TLS listener forwards to |
| redirect_target_group_arn | ARN of the target group the HTTP listener forwards to |
| certificate_arn | ARN of the wildcard certificate on the TLS listener |
| custom_domain_names | The custom wildcard domains attached to the load balancer |
| custom_certificate_arn | ARN of the certificate that covers the custom domains. Null when there are none |
| load_balancer_arn | ARN of the load balancer |
| load_balancer_dns_name | DNS name of the load balancer |
| load_balancer_zone_id | Canonical hosted zone ID of the load balancer |
| load_balancer_security_group_id | ID of the load balancer's security group |
| load_balancer_arn_suffix | ARN suffix of the load balancer, the `LoadBalancer` dimension of its `AWS/NetworkELB` metrics |
| traffic_target_group_arn_suffix | ARN suffix of the traffic target group, the `TargetGroup` dimension of the router's health metrics |
| aws_account_id | AWS account ID where the resources are deployed |
| region | AWS region where the resources are deployed |

The module definition's `apps` block hands `wildcard_domain_name`, `custom_domain_apexes`, `tls_listener_arn`, the load balancer's DNS name and zone, the `router_*` outputs, the two target group ARNs and `region` to Ravion, beside the execution environment, AWS account and VPC from its inputs.

## Limits

- One router at a time, apart from the overlap while Ravion replaces it.
- IPv4 only, and an internet-facing load balancer only.
- HTTP/1.1 between the load balancer and the router. WebSocket upgrades pass through.
- The load balancer writes no access logs.

## Testing

```bash
tofu init -backend=false
tofu test
```

`tofu test` plans the module against mocked providers.
