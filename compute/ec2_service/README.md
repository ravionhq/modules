# EC2 Service

Runs an app on a stable group of EC2 instances behind an optional Application Load Balancer, with in-place deploys pushed through SSM Run Command. Instances are managed by an Auto Scaling Group but are never replaced by deploys, so per-instance state (root volume, optional data volume) persists for the life of each instance.

Two runtimes are supported:

- **container** — each deploy pulls an image and runs the attached Docker process under supervisord.
- **manual** — deploys can check out an authenticated Git source, run release preparation commands, then start the configured long-lived command under supervisord.

Instances install the prerequisites for both runtimes at launch, so `runtime` can switch between `container` and `manual` without replacing the instance group. Supervisord owns the app in both modes and restarts it after an unexpected exit.

Container workloads that need to orchestrate sibling containers can enable `docker_socket_mount_enabled`. The deploy runner then bind-mounts `/var/run/docker.sock` at the identical path inside the app container and adds the host `docker` group's GID at container-start time. The image must include a `docker` CLI. This is Docker-outside-of-Docker: mounting the host Docker socket grants the container root-equivalent control of the instance, including the ability to start privileged containers, read the host filesystem, and use the instance role. Leave it disabled unless this level of access is required.

## How deploys work

For the **container** runtime the module creates an SSM Command document (`<name>-deploy` — the name is a platform contract derived from the group name) that encodes the whole in-place deploy for one instance:

1. Rebuild the app env file: Terraform-rendered plain values, plus secret values fetched on the instance from Secrets Manager / SSM Parameter Store.
2. Drain: deregister the instance from the target group and wait (skipped in worker mode, and when the instance is the only registered target — with nothing to shift traffic to, draining only lengthens the outage).
3. Swap the release: `docker pull`, then update the supervisord-managed container process.
4. Health gate: poll `http://localhost:<app_port><deploy_health_check_path>` until healthy, or fail the command.
5. Re-register the instance with the target group and wait until in service.

An orchestrator (the Ravion deploy manager) runs this document against the Auto Scaling Group's instances with its own batching and failure policy, passing:

| Parameter | Value |
|-----------|-------|
| `imageUri` | Full image URI including tag or digest |
| `deployId` | Optional release identifier |

The module definition exposes the rolling deployment batch and failure limits. It defaults to one instance at a time and stops after the first failure. The SSM script timeout applies per instance; the module deployment has a separate 24-hour overall safety limit.

For the **manual** runtime the document (same `<name>-deploy` name) takes a `commands` parameter and an optional Git source. When source is present, the instance fetches a temporary credential from SSM Parameter Store, performs a clean checkout under `/srv/ravion/<name>/source`, and runs both the preparation commands and `manual_start_command` from the selected base path. When source is absent, commands keep their existing working-directory behavior. Any failure stops the deploy. The start command must remain in the foreground rather than daemonizing. Draining and health checking are up to the preparation commands.

App stdout and stderr are shipped to `/ravion/ec2/<name>`. Streams use `deployment/<deployId>/instance/<instance-id>`, which keeps every deployment and EC2 instance separate. The SSM deploy script tees its stdout and stderr into the same instance stream while preserving the native SSM command output.

New instances launched by the Auto Scaling Group boot from the launch template but hold no release until the orchestrator repeats the deploy against them.

## App log rotation

Supervisord rotates the on-instance app log rather than letting a crash-looping process fill the root volume: `log_rotation_max_size_mb` (default 20) and `log_rotation_backup_count` (default 5) bound on-instance usage to `(backups + 1) * max size` per deployment log. The module writes the supervisord program config on every deploy, after any deploy commands run, so these settings cannot be overridden from a deploy command; change them through the module inputs instead. Replacement instances get the same configuration from the launch template.

## Choosing an instance type

Pick the family that fits the workload, then the newest generation of that family the target region actually offers.

| Family | Memory per vCPU | Use for |
|--------|-----------------|---------|
| `t` burstable | 0.5-4 GB | Small or spiky services, development and staging environments, low-volume workers |
| `m` general purpose | 4 GB | Web services and workers with no strong CPU or memory bias |
| `c` compute optimized | 2 GB | CPU-bound work such as request-heavy APIs, transcoding, or compilation |
| `r` memory optimized | 8 GB | Memory-bound work such as large heaps, in-process caches, or a local database |

In `m8g.large`, the digit is the generation and the letters after it identify the processor: `g` is AWS Graviton (`arm64`), `i` is Intel, `a` is AMD, and older families such as `m5` or `t3` carry no processor letter. A `-flex` variant such as `m8i-flex` costs less for workloads that do not sustain high CPU.

**Always use the highest generation number available for the chosen family.** Each generation is faster and cheaper per unit of work than the one below it, so `m8g` beats `m7g`, which beats `m6i`. Do not copy an instance type from an example (including the ones below), an older project, or an AI assistant's memory — those are typically one or two generations behind current, which pays more for less performance. Query the region instead:

```sh
ravion values aws/ec2/instances --aws-account-id <account-id> --region us-east-1
```

That lists exactly what the account and region support, from the same source as the Instance type list in the Ravion config form. Newest generations reach the largest regions first, so a region can top out a generation behind, and that list is region-level: a type offered in the region may still be missing from one Availability Zone, so if capacity fails in one subnet, place the group across more AZs. Burstable is the exception to the generation rule: `t4g`, `t3`, and `t3a` are still the newest burstable families, because AWS has not released a newer one.

Prefer Graviton whenever the workload can run on it: best price and performance in every family that offers it, and with `ami_id` left null the module reads `supported_architectures` from the selected instance type and resolves the matching `arm64` Amazon Linux 2023 AMI, so no other input changes. A custom `ami_id` is used as given, so it must already match the instance type's architecture. The container image (`container` runtime) or host-installed dependencies (`manual` runtime) must build for `arm64`. Use an Intel or AMD type when something in the stack is `x86_64`-only.

Then right-size from measurement: start with the smallest size in the family that holds the working set, watch the instances' CPU and memory utilization, and move up a size or set `cpu_autoscaling_enabled` from there.

Changing `instance_type` produces a new launch template version that applies to instances launched afterwards. Running instances keep their current type until recycled, and a Graviton/x86 switch changes the AMI for new instances only, so the group can briefly run both architectures mid-recycle. Either keep multi-architecture images during that window or recycle every instance promptly.

## Usage

The instance types in these examples are illustrative, not recommendations — select yours as described above.

### Web service running a container

```hcl
module "web" {
  source = "git::https://github.com/ravionhq/modules.git//compute/ec2_service?ref=v1.0.0"

  name       = "my-web"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-aaa", "subnet-bbb"]

  runtime       = "container"
  instance_type = "m8g.large"
  min_size      = 2
  max_size      = 4

  app_port                = 3000
  deploy_health_check_path = "/health"

  ecr_repository_creation_enabled = true

  load_balancer_attachment = {
    target_group = {
      port = 3000
      health_check = {
        path = "/health"
      }
    }
    listener_rules = [
      {
        listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/shared/abc/def"
        conditions = [
          { type = "host-header", values = ["app.example.com"] }
        ]
      }
    ]
  }
  load_balancer_security_group_id = "sg-0123456789abcdef0"

  environment_variables = [
    { name = "NODE_ENV", value = "production" }
  ]
  secrets = [
    { name = "DATABASE_URL", value_from = "arn:aws:ssm:us-east-1:123456789012:parameter/my-app/database-url" }
  ]
}
```

### Worker with manual command deploys

```hcl
module "worker" {
  source = "git::https://github.com/ravionhq/modules.git//compute/ec2_service?ref=v1.0.0"

  name       = "my-worker"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-aaa", "subnet-bbb"]

  runtime       = "manual"
  instance_type = "m8g.large"

  manual_start_command = "cd /srv/app && ./bin/worker"

  data_volume_creation_enabled = true
  data_volume_size             = 50
}
```

Deploys then run your release preparation commands on every instance, with the app env file refreshed and loaded first:

```sh
aws ssm send-command \
  --document-name my-worker-deploy \
  --targets Key=tag:aws:autoscaling:groupName,Values=my-worker \
  --parameters commands='["cd /srv/app && git pull","cd /srv/app && ./bin/migrate"]'
```

## Storage and durability

- The root volume and optional data volume are per-instance EBS. They are durable for the life of the instance: deploys, restarts, and stack updates never replace an instance, so local files such as an embedded database stay in place at local-disk latency, exactly as on an EC2 instance you launch yourself.
- They are deleted with the instance, which happens for exactly three reasons: you terminate or recycle it (for example to roll out a new AMI), the group scales in, or it fails its Auto Scaling health check. Keep backups (EBS snapshots, dumps to S3) for critical data instead of avoiding local storage.
- `health_check_type` defaults to `EC2`, which is the AWS instance/system status check — unreachable instance, broken boot or network state, failed underlying host. It ignores application state: a crashed app is restarted in place by supervisord, and a failing HTTP health check never replaces an instance. So health-driven replacement is rare and tied to hardware or hypervisor failure. Setting `health_check_type = "ELB"` makes load balancer health replace instances instead, which also breaks in-place deploys (they briefly deregister the instance).
- Mount an EFS file system (`efs_*` variables) when several instances must share the same files, or when a replacement instance must find data already in place; it is mounted on every instance and, for the container runtime, bind-mounted into the app container.
- When `docker_socket_mount_enabled` is enabled, the data volume and EFS host paths are mapped identically inside the app container. This lets sibling containers started through the host Docker socket resolve those same host-path binds correctly.
- Launch template changes (AMI, user data, volumes) intentionally apply only to newly launched instances; there is no instance refresh, so applying a new AMI never replaces running instances by itself. Recycling instances to pick up the new AMI is a replacement, and it deletes their volumes.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

Instances need outbound access to SSM, ECR/S3, CloudWatch Logs, PyPI for the pinned Supervisor installation, and (when secrets are configured) Secrets Manager (NAT gateway, public IPs, or VPC endpoints). The default AMI is Amazon Linux 2023; custom AMIs must run cloud-init and include the SSM agent.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources (1-28 chars) | `string` | n/a | yes |
| tags | Tags for all resources | `map(string)` | `{}` | no |
| region | AWS region (null = provider region) | `string` | `null` | no |
| vpc_id | VPC for the instances | `string` | n/a | yes |
| subnet_ids | Subnets for the Auto Scaling Group | `list(string)` | n/a | yes |
| public_ip_assignment_enabled | Assign public IPs to instances | `bool` | `false` | no |
| additional_security_group_ids | Extra security groups on the instances | `list(string)` | `[]` | no |
| direct_access_cidr_blocks | IPv4 CIDRs allowed to reach the app port directly | `list(string)` | `[]` | no |
| runtime | `container` or `manual` | `string` | n/a | yes |
| docker_socket_mount_enabled | Mount the host Docker socket and add the host `docker` group GID (container mode only; grants root-equivalent control of the instance) | `bool` | `false` | no |
| app_port | Port the app listens on | `number` | `null` | no |
| container_start_command | Optional container start command overriding the image CMD | `string` | `null` | no |
| manual_start_command | Long-running foreground manual app command managed by supervisord | `string` | `null` | yes for manual |
| environment_variables | Plain env vars written to the app env file | `list(object)` | `[]` | no |
| secrets | Secret env vars fetched on-instance from Secrets Manager / SSM Parameter Store (`{name, value_from}`) | `list(object)` | `[]` | no |
| deploy_health_check_path | Local HTTP path gating deploy success | `string` | `null` | no |
| deploy_timeout_seconds | Per-instance deploy script timeout | `number` | `1200` | no |
| instance_type | EC2 instance type; use the newest generation the region offers (see "Choosing an instance type") | `string` | n/a | yes |
| ami_id | Custom AMI (null = latest AL2023) | `string` | `null` | no |
| key_name | SSH key pair name | `string` | `null` | no |
| root_volume_size | Root EBS volume size (GB) | `number` | `30` | no |
| root_volume_type | Root EBS volume type | `string` | `"gp3"` | no |
| data_volume_creation_enabled | Attach a formatted per-instance data volume | `bool` | `false` | no |
| data_volume_size | Data volume size (GB) | `number` | `20` | no |
| data_volume_type | Data volume type | `string` | `"gp3"` | no |
| data_volume_mount_path | Host mount path for the data volume | `string` | `"/data"` | no |
| additional_user_data | Extra shell script appended to bootstrap | `string` | `""` | no |
| min_size | Minimum instances | `number` | `1` | no |
| max_size | Maximum instances | `number` | `1` | no |
| desired_capacity | Desired instances (null = group-managed) | `number` | `null` | no |
| health_check_type | ASG health check: `EC2` or `ELB` | `string` | `"EC2"` | no |
| health_check_grace_period | Seconds before ASG health checks apply | `number` | `300` | no |
| cpu_autoscaling_enabled | Scale on average CPU utilization | `bool` | `false` | no |
| cpu_target_value | CPU utilization target (%) | `number` | `70` | no |
| load_balancer_attachment | Target group + listener rules (null = worker mode) | `object` | `null` | no |
| load_balancer_security_group_id | ALB security group allowed to reach the app port | `string` | `null` | no |
| efs_enabled | Mount an EFS file system on every instance | `bool` | `false` | no |
| efs_file_system_id | EFS file system ID | `string` | `null` | no |
| efs_access_point_id | EFS access point to mount through | `string` | `null` | no |
| efs_client_security_group_id | EFS client security group attached to instances | `string` | `null` | no |
| efs_mount_path | Host mount path for EFS | `string` | `"/mnt/efs"` | no |
| ecr_repository_creation_enabled | Create an ECR repository for built images | `bool` | `false` | no |
| ecr_force_deletion_enabled | Delete the ECR repository even with images | `bool` | `false` | no |
| ecr_scan_on_push_enabled | Scan images for vulnerabilities after push | `bool` | `true` | no |
| log_retention_in_days | CloudWatch app log retention | `number` | `30` | no |
| log_rotation_max_size_mb | Size at which supervisord rotates the on-instance app log | `number` | `20` | no |
| log_rotation_backup_count | Rotated app log files kept on the instance | `number` | `5` | no |

## Outputs

| Name | Description |
|------|-------------|
| autoscaling_group_name | Name of the Auto Scaling Group deploys target |
| autoscaling_group_arn | ARN of the Auto Scaling Group |
| ssm_document_name | Name of the SSM deploy document |
| ssm_document_arn | ARN of the SSM deploy document |
| ecr_repository_arn | ARN of the service ECR repository (when created) |
| ecr_repository_url | URL of the service ECR repository (when created) |
| target_group_arn | ARN of the service target group (when attached) |
| target_group_arn_suffix | Target group ARN suffix for CloudWatch dimensions |
| security_group_id | ID of the instance security group |
| instance_role_arn | ARN of the instance IAM role |
| log_group_name | CloudWatch log group receiving app logs |
| log_stream_prefix | Prefix of deployment- and instance-scoped app log streams |
| aws_account_id | AWS account ID |
| region | AWS region |
