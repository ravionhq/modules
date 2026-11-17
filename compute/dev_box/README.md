# Dev Box Module

Creates a standalone EC2 instance to log in to and use as a cloud computer. It runs no application code: there is no load balancer, Auto Scaling group, or deploy process, just one long-lived instance with a persistent encrypted disk.

- Session Manager login by default, with no inbound ports or SSH keys
- Optional SSH from specific CIDR blocks, with an optional public IP
- Latest Ubuntu 24.04 LTS or Amazon Linux 2023 image for the instance type's architecture, or a custom AMI
- New base image releases and first boot script edits never rebuild the box
- Optional managed IAM policies for AWS access from the box
- Optional EventBridge Scheduler stop on a cron schedule to save cost
- IMDSv2 required

Includes the `rvn-aws-dev-box` Ravion module definition.

## Usage

```hcl
module "dev_box" {
  source = "git::https://github.com/ravionhq/modules.git//compute/dev_box?ref=rvn-aws-dev-box@0.1.0"

  name          = "alice-dev"
  vpc_id        = "vpc-0123456789abcdef0"
  subnet_ids    = ["subnet-0123456789abcdef0"]
  instance_type = "m7i.xlarge"

  root_volume_size = 200
  iam_policy_arns  = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  auto_stop_enabled             = true
  auto_stop_schedule_expression = "cron(0 19 ? * MON-FRI *)"
  auto_stop_timezone            = "America/New_York"
}
```

Log in with the Session Manager plugin for the AWS CLI:

```bash
aws ssm start-session --region us-east-1 --target <instance-id>
```

Sessions start as `ssm-user`. Run `sudo su - ubuntu` (or `ec2-user` on Amazon Linux) to switch to the image's default user.

## Lifecycle

| Change | Effect |
| --- | --- |
| `instance_type` | Stops and restarts the instance; the disk is kept. A type with a different CPU architecture (x86 and Graviton) is refused. |
| `root_volume_size` increase | Grows the volume in place; grow the filesystem from inside the box. |
| New default image release | Ignored. |
| `user_data` | Ignored after the first boot. |
| `ami_id`, `operating_system` (without `ami_id`), `key_name`, `subnet_ids[0]`, `public_ip_assignment_enabled`, `root_volume_kms_key_id` | Replaces the instance and erases its disk. |

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name prefix for the instance, security group, IAM role, and schedule. 1-28 lowercase letters, numbers, and hyphens. | `string` | n/a | yes |
| vpc_id | VPC that the dev box runs in. | `string` | n/a | yes |
| subnet_ids | Subnets the dev box may run in. The instance is placed in the first one. | `list(string)` | n/a | yes |
| instance_type | EC2 instance type. | `string` | n/a | yes |
| region | AWS region. Defaults to the provider region. | `string` | `null` | no |
| operating_system | `ubuntu-24.04` or `al2023`, used when `ami_id` is not set. | `string` | `"ubuntu-24.04"` | no |
| ami_id | Custom AMI. Overrides `operating_system`. | `string` | `null` | no |
| root_volume_size | Root volume size in GiB. | `number` | `100` | no |
| root_volume_type | Root volume type: `gp3` or `gp2`. | `string` | `"gp3"` | no |
| root_volume_kms_key_id | KMS key ARN for root volume encryption. Defaults to the account's default EBS key. | `string` | `null` | no |
| public_ip_assignment_enabled | Assign a public IPv4 address. Requires a public subnet. | `bool` | `false` | no |
| additional_security_group_ids | Additional security groups attached to the dev box. | `list(string)` | `[]` | no |
| ssh_allowed_cidr_blocks | IPv4 CIDR blocks allowed to reach port 22. | `list(string)` | `[]` | no |
| key_name | Existing EC2 key pair installed for SSH. | `string` | `null` | no |
| ssm_enabled | Attach `AmazonSSMManagedInstanceCore` for Session Manager access. | `bool` | `true` | no |
| iam_policy_arns | Managed IAM policy ARNs attached to the instance role. | `list(string)` | `[]` | no |
| user_data | Shell script run as root on the first boot only. | `string` | `""` | no |
| termination_protection_enabled | Block terminating the instance through the EC2 API. | `bool` | `false` | no |
| auto_stop_enabled | Stop the dev box on a schedule. | `bool` | `false` | no |
| auto_stop_schedule_expression | EventBridge Scheduler `cron()` expression for auto stop. | `string` | `"cron(0 19 * * ? *)"` | no |
| auto_stop_timezone | IANA time zone for the auto stop schedule. | `string` | `"UTC"` | no |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| instance_id | ID of the dev box instance. |
| instance_arn | ARN of the dev box instance. |
| region | AWS region of the dev box. |
| availability_zone | Availability zone of the dev box. |
| private_ip | Private IPv4 address. |
| private_dns | Private DNS name. |
| public_ip | Public IPv4 address, or null when none is assigned. Changes on stop and start. |
| ami_id | AMI the dev box was launched from. |
| login_user | Default SSH login user for the base image, or null for a custom AMI. |
| security_group_id | ID of the dev box security group. |
| iam_role_name | Name of the instance IAM role. |
| iam_role_arn | ARN of the instance IAM role. |
| ssm_start_session_command | AWS CLI command that opens a Session Manager shell, or null when Session Manager is off. |
| auto_stop_schedule_arn | ARN of the auto stop schedule, or null when auto stop is off. |
