# alterNAT

New NAT instances default to the latest Amazon Linux 2023 minimal kernel 6.18 image for their architecture. `nat_instance_ami_id` still overrides this default. An image-selector change does not prove existing instances are patched: replace them through the failover lifecycle and verify their running kernels afterward.

Highly available NAT instances for an existing VPC, using Chime's [alterNAT](https://github.com/chime/terraform-aws-alternat) (`chime/alternat/aws`, pinned to `0.10.4`). NAT instances carry private subnet egress with no per-GB processing charge. A connectivity tester in each availability zone fails the route over to a NAT gateway when a NAT instance is unhealthy, and restores it once the instance recovers.

The module wraps the official alterNAT module and adds:

- **Route table discovery** from private subnet IDs, including subnets on the VPC's main route table
- **Automatic placement**: one NAT instance per availability zone that has its own private route table, or a single NAT instance
- **Fallback to an existing NAT gateway**, discovered in the VPC, or standby NAT gateways created per NAT instance
- **Zip-packaged Lambda functions**, so no container image has to be built or pushed. The zip is committed in `lambda/`, so a saved plan applies on any machine; `tests/lambda_zip.tftest.hcl` checks it against the pinned alterNAT release
- **Architecture from the instance type**, Graviton by default
- **Names derived from `name`**, so several VPCs in one account and region can each run alterNAT
- **Optional EC2 interface endpoint and S3/DynamoDB gateway endpoints**
- **Plan-time checks** for misconfiguration (missing fallback NAT gateway, Elastic IP count, subnets outside the VPC)

## Usage

### Existing VPC with a NAT gateway

```hcl
module "alternat" {
  source = "git::https://github.com/ravionhq/modules.git//networking/alternat?ref=v1.0.0"

  region             = "us-west-2"
  name               = "production"
  vpc_id             = "vpc-0123456789abcdef0"
  public_subnet_ids  = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  private_subnet_ids = ["subnet-0cccccccccccccccc", "subnet-0dddddddddddddddd"]

  s3_gateway_endpoint_enabled = true
}
```

The VPC's NAT gateway becomes the fallback, and alterNAT takes over the `0.0.0.0/0` route of each private subnet's route table.

### VPC without a NAT gateway

```hcl
module "alternat" {
  source = "git::https://github.com/ravionhq/modules.git//networking/alternat?ref=v1.0.0"

  region             = "us-west-2"
  name               = "production"
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  fallback_nat_gateway_mode = "create"
}
```

## Placement

1. Each private subnet's route table is discovered from its association (the main route table when it has none).
2. With `high_availability_enabled = true`, each route table is served by a NAT instance in an availability zone it serves, in that zone's first listed public subnet. A route table shared across zones gets one NAT instance.
3. With `high_availability_enabled = false`, one NAT instance serves every route table.

A route table that public subnets also use (including the main route table when neither has an explicit association) fails the plan: replacing its Internet Gateway route would cut the NAT instances off from the internet.

The placement logic lives in `modules/placement` and is covered by `tests/placement.tftest.hcl`.

## Failover

| `fallback_nat_gateway_mode` | Fallback |
| --- | --- |
| `existing` (default) | `fallback_nat_gateway_id`, else the VPC's only public NAT gateway, else the public NAT gateway in each NAT instance's public subnet. Private NAT gateways are never used. |
| `create` | A standby NAT gateway created in each NAT instance's public subnet |

The selection logic lives in `modules/fallback` and is covered by `tests/fallback.tftest.hcl`, including VPCs with both public and private NAT gateways.

Failover keeps connectivity, but connections through a failed or replaced NAT instance are dropped. During failover, traffic leaves from the NAT gateway's public IP.

When the VPC's Terraform also manages a `0.0.0.0/0` route to a NAT gateway, its next apply points the route back at the NAT gateway; with `nat_restore_enabled` (default), alterNAT moves it back to the NAT instance within a minute.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |
| archive | >= 2.7.0 |
| cloudinit | >= 2.3.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region of the VPC. | `string` | n/a | yes |
| name | Name prefix for every resource; unique per account and region. 1-28 lowercase letters, numbers, and hyphens. | `string` | n/a | yes |
| vpc_id | VPC whose private subnets egress through the NAT instances. | `string` | n/a | yes |
| public_subnet_ids | Public subnets the NAT instances run in. | `list(string)` | n/a | yes |
| private_subnet_ids | Private subnets whose egress the NAT instances take over. | `list(string)` | n/a | yes |
| high_availability_enabled | One NAT instance per availability zone with its own private route table. | `bool` | `true` | no |
| nat_instance_type | EC2 instance type; the AMI architecture follows it. | `string` | `"c7gn.medium"` | no |
| nat_instance_ami_id | AMI for the NAT instances. Defaults to the latest Amazon Linux 2023 minimal AMI. | `string` | `null` | no |
| nat_instance_eip_allocation_ids | Pre-allocated Elastic IPs, one per NAT instance. | `list(string)` | `[]` | no |
| max_instance_lifetime_days | Replace NAT instances after this many days; 0 never replaces. | `number` | `14` | no |
| allowed_cidr_blocks | IPv4 CIDR blocks besides the VPC's that may route through the NAT instances. | `list(string)` | `[]` | no |
| allowed_security_group_ids | Security groups that may route through the NAT instances. | `list(string)` | `[]` | no |
| ssm_enabled | Session Manager access to the NAT instances. Required for NAT restore. | `bool` | `true` | no |
| cloudwatch_agent_enabled | Publish per-interface network metrics with the CloudWatch agent. | `bool` | `false` | no |
| nat_instance_user_data_pre_install | Shell script run before alterNAT configures NAT. | `string` | `""` | no |
| nat_instance_user_data_post_install | Shell script run after alterNAT configures NAT. | `string` | `""` | no |
| nat_instance_key_name | EC2 key pair for SSH access. | `string` | `null` | no |
| fallback_nat_gateway_mode | `existing` reuses the VPC's NAT gateways; `create` creates standby ones. | `string` | `"existing"` | no |
| fallback_nat_gateway_id | With `existing`, the NAT gateway every NAT instance fails over to. | `string` | `null` | no |
| fallback_nat_gateway_eip_allocation_ids | With `create`, Elastic IPs for the standby NAT gateways, keyed by availability zone. | `map(string)` | `{}` | no |
| nat_restore_enabled | Move traffic back to a recovered NAT instance. | `bool` | `true` | no |
| connectivity_check_urls | URLs checked every minute; failover when all are unreachable. | `list(string)` | `["https://www.example.com", "https://www.google.com"]` | no |
| ec2_endpoint_enabled | EC2 interface endpoint so failover works while internet egress is down. | `bool` | `true` | no |
| s3_gateway_endpoint_enabled | Free S3 gateway endpoint on the managed route tables. | `bool` | `false` | no |
| dynamodb_gateway_endpoint_enabled | Free DynamoDB gateway endpoint on the managed route tables. | `bool` | `false` | no |
| tags | Tags for all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| aws_account_id | AWS account ID the NAT instances run in. |
| region | AWS region the NAT instances run in. |
| vpc_id | ID of the VPC. |
| nat_instances | Per NAT instance: availability zone, public subnet, route tables, Auto Scaling group, connectivity tester function and log group. |
| nat_instance_public_ips | Public IPs traffic leaves from while the NAT instances are healthy. |
| nat_instance_availability_zones | Availability zones with a NAT instance. |
| nat_instance_security_group_id | Security group of the NAT instances. |
| nat_instance_architecture | CPU architecture of the NAT instances. |
| autoscaling_group_names | Auto Scaling groups of the NAT instances. |
| route_table_ids | Private route tables whose `0.0.0.0/0` route alterNAT manages. |
| route_table_nat_availability_zones | Availability zone of the NAT instance serving each route table. |
| fallback_nat_gateway_id | NAT gateway every NAT instance fails over to; empty when each uses the one in its own subnet. |
| fallback_nat_gateway_ids | NAT gateways the NAT instances fail over to: existing ones, or the standby ones in `create` mode. |
| fallback_nat_gateway_public_ips | Public IPs of standby NAT gateways created in `create` mode. |
| connectivity_tester_function_names | Connectivity tester Lambda functions. |
| connectivity_tester_log_group_names | Log groups of the connectivity tester Lambda functions. |
| autoscaling_hook_function_name | Lambda function that fails over when a NAT instance terminates. |
| autoscaling_hook_log_group_name | Log group of the Auto Scaling hook Lambda function. |
| ec2_vpc_endpoint_id | EC2 interface endpoint ID, if created. |
| s3_vpc_endpoint_id | S3 gateway endpoint ID, if created. |
| dynamodb_vpc_endpoint_id | DynamoDB gateway endpoint ID, if created. |

## Testing

```bash
tofu init -backend=false
tofu test
```

Tests mock the AWS provider and the upstream alterNAT module, so they need no AWS credentials.
