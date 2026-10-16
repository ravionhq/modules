# App Cluster Module

This module creates what the apps of an App Cluster run on and are served through: a sandbox pool whose hosts run each app in its own sandbox, and an internet-facing Network Load Balancer with a Ravion-managed wildcard domain and certificate, in front of a router that forwards each app hostname to its sandbox and wakes a paused app when a request arrives for it.

Ravion runs the router instance and the sandbox hosts. This module creates everything they run in: the security groups, the router's IAM role and instance profile, the load balancer and its target groups, and the pool's registration. Requests travel from the browser to the load balancer, to the router, to the sandbox host, all inside your AWS account.

## What Terraform creates

| Resource | Purpose |
| --- | --- |
| Network Load Balancer | Internet-facing, cross-zone, with its own security group |
| TLS listener on 443 | Terminates TLS with the wildcard certificate and forwards to the router on TCP 8080 |
| TCP listener on 80 | Forwards to the router on TCP 8081, where plain HTTP is redirected to HTTPS |
| Two target groups | Instance targets with the client address preserved and a 30 second deregistration delay, health checked over HTTP on `/healthz`, port 8082. Ravion registers the router instance in both |
| Wildcard certificate and DNS record | `*.<name>.<apex>` on Ravion's managed apex, where the name is `ravion_domain_name` or, when that is unset, the module instance given id, issued through the `ravion_aws_acm_certificate` resource and pointed at the load balancer |
| Custom domain certificate and domains | One certificate for every entry of `domains`, attached to the TLS listener beside the wildcard certificate, and one `ravion_domain` per entry pointed at the load balancer. Created only with `domains` |
| Three security groups | One for the load balancer, one for the router, one for the sandbox hosts |
| Router IAM role and instance profile | Lets the router publish its metrics to CloudWatch in the `Ravion/AppRouter` namespace. With `ssm_enabled`, also Session Manager access for operators. Ravion launches the router with the instance profile |
| Sandbox pool | A `ravion_sandbox_pool`: the execution environment whose sandbox pool runs the apps, in `host_subnet_id` and the sandbox hosts' security group |

The module creates no router instance, launch template or Auto Scaling group. Ravion launches the router in `router_subnet_ids` with the router's security group and instance profile, registers it in both target groups once it holds its routes, and replaces it the same way: the new router is registered before the old one is drained and terminated.

## Usage

Inside Ravion, create a module instance of `rvn-app-cluster`. The stack run supplies `module_instance_id`, `module_instance_given_id`, `ravion_api_url` and the provider credentials.

```hcl
module "app_cluster" {
  source = "git::https://github.com/ravionhq/modules.git//compute/app_cluster?ref=rvn-app-cluster@0.1.0"

  name               = "apps"
  module_instance_id = "minst_..."
  ravion_domain_name = "apps"

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  router_subnet_ids = module.vpc.private_subnet_ids
  host_subnet_id    = module.vpc.private_subnet_ids[0]

  tags = {
    Environment = "staging"
  }
}
```

Choose the hosts and keep one parked and ready:

```hcl
module "app_cluster" {
  source = "git::https://github.com/ravionhq/modules.git//compute/app_cluster?ref=rvn-app-cluster@0.1.0"

  name               = "apps"
  module_instance_id = "minst_..."

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  router_subnet_ids = module.vpc.private_subnet_ids
  host_subnet_id    = module.vpc.private_subnet_ids[0]

  host_instance_types = [
    { type = "c8id.4xlarge" },
    { type = "m8id.4xlarge", disk_gib = 200 },
  ]
  host_capacity_types = ["ON_DEMAND", "SPOT"]
  host_reserve_policy = { type = "FIXED", value = 1 }
  max_hosts           = 20
}
```

Outside a Ravion pipeline, set `module_instance_id` as above and export `RAVION_BASE_URL` and `RAVION_API_KEY` for the `ravion` provider before applying.

## The sandbox pool

`ravion_sandbox_pool` registers an execution environment with a sandbox pool, owned by this module instance. Ravion then sets up the pool's host role, chunk store and launch templates, and launches hosts in `host_subnet_id` and the sandbox hosts' security group when apps need room. The `execution_environment_id` output is its id.

| Setting | Variable | Default |
| --- | --- | --- |
| Instance types, each with its root volume size, IOPS and throughput | `host_instance_types` | Empty: Ravion chooses from the region's c8id, m8id, r8id, i7i and i7ie types that support nested virtualization |
| Markets | `host_capacity_types` | `["ON_DEMAND"]`. `ON_DEMAND` is required; `SPOT` adds Spot hosts |
| Hosts kept parked and ready | `host_reserve_policy` | `NONE`. `FIXED` keeps `value` hosts; `PEAK` and `ROLLING_AVERAGE` follow the last `window_days` of use |
| Most hosts at once, parked included | `max_hosts` | `10` |

Ravion refuses to delete the pool while it runs sandboxes, so destroying a cluster that still has apps fails. Delete the apps first.

## Security groups

| Group | Inbound | Outbound |
| --- | --- | --- |
| Load balancer | TCP 443 and 80 from `ingress_cidr_blocks` | TCP 8080, 8081 and 8082 to the router's group |
| Router | TCP 8080, 8081 and 8082 from the load balancer's group | TCP 443 to any address; TCP 20000-20999 to the sandbox hosts' group |
| Sandbox hosts | TCP 20000-20999 from the router's group | Any IPv4 address |

No CIDR reaches the router or the hosts. The router's outbound HTTPS serves the Ravion API and AWS APIs; a Ravion API on a port other than 443 adds that port. Ports 20000-20999 are where sandbox hosts serve the apps' ports, the last one being the hosts' own health port, and the router can open no other connection inside the VPC.

The sandbox hosts' rule that admits the router (`ravion app router to sandbox hosts`) belongs to this module, so a destroy removes it with both groups. To let the apps reach a database or another service, allow the `host_security_group_id` output in that resource's security group.

## Session Manager

`ssm_enabled` attaches the `AmazonSSMManagedInstanceCore` policy to the router's role. Turn it off to leave the role with only the permission to publish the router's metrics.

## Metrics

The router publishes request metrics to CloudWatch every minute, in the `Ravion/AppRouter` namespace of the module's account and region. The router's role allows `cloudwatch:PutMetricData` with the condition `cloudwatch:namespace = Ravion/AppRouter`. The action has no resource-level permissions, so the namespace condition is its only scope.

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

The module's definition charts these on the Metrics tab beside the load balancer's `AWS/NetworkELB` metrics and the pool's host minutes from the `BusyHosts` series its hosts publish in `Ravion/SandboxHost`.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |
| ravion (`providers.ravion.com/ravion/ravion`) | A release with the `ravion_sandbox_pool` resource, configured from `RAVION_BASE_URL` / `RAVION_API_KEY` |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name of the load balancer and the prefix of every other resource (1-32 characters) | `string` | n/a | yes |
| module_instance_id | Ravion module instance id (`minst_*`) of this App Cluster. Injected as `TF_VAR_module_instance_id` inside a stack run | `string` | n/a | yes |
| vpc_id | VPC of the load balancer, the router and the sandbox hosts | `string` | n/a | yes |
| public_subnet_ids | Public subnets for the load balancer | `list(string)` | n/a | yes |
| router_subnet_ids | Subnets Ravion may launch the router in, in Availability Zones the public subnets cover. The router needs outbound HTTPS | `list(string)` | n/a | yes |
| host_subnet_id | Subnet Ravion launches the sandbox hosts in. The hosts need outbound internet access | `string` | n/a | yes |
| host_instance_types | Instance types the pool may launch, each `{ type, disk_gib = 130, disk_iops = 3000, disk_throughput_mbps = 125 }`. Empty lets Ravion choose | `list(object)` | `[]` | no |
| host_capacity_types | Markets the pool buys hosts in: `ON_DEMAND`, and `SPOT` | `list(string)` | `["ON_DEMAND"]` | no |
| host_reserve_policy | Hosts kept parked and ready: `{ type = NONE \| FIXED \| PEAK \| ROLLING_AVERAGE, window_days = 7, value = 0 }` | `object` | `{ type = "NONE" }` | no |
| max_hosts | Most hosts the pool runs at once, parked hosts included (1-100) | `number` | `10` | no |
| ingress_cidr_blocks | IPv4 CIDR blocks allowed to reach the load balancer on 443 and 80. An empty list allows none | `list(string)` | `["0.0.0.0/0"]` | no |
| ssl_policy | Security policy of the TLS listener | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| ssm_enabled | Add Session Manager access to the router's role | `bool` | `true` | no |
| ravion_api_url | Origin of the Ravion API. A port other than 443 is added to the router's outbound rules. Injected as `TF_VAR_ravion_api_url` inside a stack run | `string` | `null` | no |
| ravion_domain_name | Name leaf of the wildcard domain: Ravion issues `*.<name>.<apex>`. Null uses the module instance given id | `string` | `null` | no |
| module_instance_given_id | The module instance's given id, the default leaf of the wildcard domain. Injected as `TF_VAR_module_instance_given_id` inside a stack run | `string` | `null` | no |
| domains | Custom wildcard domains attached to the load balancer, each `*.<domain>` in a DNS zone you control. At most 10 | `list(string)` | `[]` | no |
| ravion_aws_account_id | Ravion AWS account record id the certificate is issued in and the pool runs in. Null detects it from the run's AWS credentials | `string` | `null` | no |
| region | AWS region. Null uses the provider's region | `string` | `null` | no |
| tags | Tags to assign to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| execution_environment_id | The execution environment (`ee_*`) whose sandbox pool runs the apps |
| wildcard_domain_name | The apex apps are served under, without `*.` |
| router_subnet_ids | The subnets Ravion may launch the router in |
| router_security_group_id | ID of the router's security group |
| router_instance_profile_name | Name of the router's instance profile; its role has the same name |
| traffic_target_group_arn | ARN of the target group the TLS listener forwards to |
| redirect_target_group_arn | ARN of the target group the HTTP listener forwards to |
| host_security_group_id | ID of the sandbox hosts' security group |
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

The module definition's `apps` block hands `execution_environment_id`, `wildcard_domain_name`, the `router_*` outputs and the two target group ARNs to Ravion.

## Limits

- One router at a time, apart from the overlap while Ravion replaces it.
- IPv4 only, and an internet-facing load balancer only.
- HTTP/1.1 between the load balancer and the router. WebSocket upgrades pass through.
- The sandbox hosts launch in one subnet.
- The load balancer writes no access logs.

## Testing

```bash
tofu init -backend=false
tofu test
```

`tofu test` plans the module against mocked providers.
