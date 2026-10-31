mock_provider "aws" {
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["x86_64"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_resource {
    target = aws_iam_instance_profile.instance
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/stateful-app-instance"
    }
  }

  override_resource {
    target = aws_iam_role.dlm
    values = {
      arn = "arn:aws:iam::123456789012:role/stateful-app-dlm"
    }
  }

  override_resource {
    target = module.instance_security_group.aws_security_group.this
    values = {
      id = "sg-12345678"
    }
  }

  override_resource {
    target = aws_launch_template.app
    values = {
      id = "lt-12345678"
    }
  }

  override_resource {
    target = aws_lb_target_group.app
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/stateful-app/1234567890abcdef"
    }
  }
}

variables {
  name          = "stateful-app"
  region        = "us-east-1"
  vpc_id        = "vpc-12345678"
  subnet_ids    = ["subnet-12345678"]
  instance_type = "t3.micro"
  ami_id        = "ami-12345678"
  runtime       = "container"
}

################################################################################
# Scheduled data volume snapshots
################################################################################

run "snapshots_default_on_with_a_data_volume" {
  command = plan

  variables {
    data_volume_creation_enabled = true
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.data_volume) == 1 && length(aws_iam_role.dlm) == 1 && length(aws_iam_role_policy_attachment.dlm) == 1
    error_message = "A data volume must get a snapshot policy and its role by default."
  }

  assert {
    condition = (
      aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].policy_type == "EBS_SNAPSHOT_MANAGEMENT" &&
      aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].resource_types == tolist(["INSTANCE"]) &&
      aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].target_tags == tomap({ Name = "stateful-app" })
    )
    error_message = "The policy must snapshot instances carrying the service Name tag, which existing instances already have."
  }

  assert {
    condition     = aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].parameters[0].exclude_boot_volume == true
    error_message = "Scheduled snapshots must cover the data volume only, not the boot volume."
  }

  assert {
    condition = (
      aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].schedule[0].create_rule[0].interval == 24 &&
      aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].schedule[0].create_rule[0].interval_unit == "HOURS" &&
      aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].schedule[0].create_rule[0].times == tolist(["03:00"])
    )
    error_message = "Snapshots must be taken daily at a fixed UTC time."
  }

  assert {
    condition     = aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].schedule[0].retain_rule[0].count == 7
    error_message = "Seven daily snapshots must be kept by default."
  }

  assert {
    condition = (
      aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].schedule[0].copy_tags == true &&
      aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].schedule[0].tags_to_add["ravion:snapshot-type"] == "scheduled" &&
      aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].schedule[0].tags_to_add["ravion:service"] == "stateful-app" &&
      aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].schedule[0].variable_tags["ravion:instance-id"] == "$(instance-id)"
    )
    error_message = "Scheduled snapshots must carry the volume tags plus tags identifying them as Ravion scheduled snapshots."
  }

  assert {
    condition     = aws_dlm_lifecycle_policy.data_volume[0].state == "ENABLED" && aws_dlm_lifecycle_policy.data_volume[0].execution_role_arn == "arn:aws:iam::123456789012:role/stateful-app-dlm"
    error_message = "The policy must be enabled and run as the module's DLM role."
  }

  assert {
    condition     = jsondecode(aws_iam_role.dlm[0].assume_role_policy).Statement[0].Principal.Service == "dlm.amazonaws.com"
    error_message = "Only Data Lifecycle Manager may assume the snapshot role."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.dlm[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
    error_message = "The snapshot role must use the AWS managed DLM service policy."
  }
}

run "snapshot_retention_count_is_wired" {
  command = plan

  variables {
    data_volume_creation_enabled         = true
    data_volume_snapshot_retention_count = 30
  }

  assert {
    condition     = aws_dlm_lifecycle_policy.data_volume[0].policy_details[0].schedule[0].retain_rule[0].count == 30
    error_message = "The configured retention count must reach the policy."
  }
}

run "snapshots_can_be_turned_off" {
  command = plan

  variables {
    data_volume_creation_enabled  = true
    data_volume_snapshots_enabled = false
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.data_volume) == 0 && length(aws_iam_role.dlm) == 0 && length(aws_iam_role_policy_attachment.dlm) == 0
    error_message = "Turning snapshots off must remove the policy and its role."
  }

  assert {
    condition     = output.data_volume_snapshot_policy_id == null && output.data_volume_snapshot_policy_arn == null
    error_message = "The snapshot policy outputs must be null without a policy."
  }
}

run "no_snapshots_without_a_data_volume" {
  command = plan

  variables {
    data_volume_creation_enabled  = false
    data_volume_snapshots_enabled = true
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.data_volume) == 0 && length(aws_iam_role.dlm) == 0 && length(aws_iam_role_policy_attachment.dlm) == 0
    error_message = "Without a data volume there is nothing to snapshot."
  }
}

run "no_snapshots_with_both_off" {
  command = plan

  variables {
    data_volume_creation_enabled  = false
    data_volume_snapshots_enabled = false
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.data_volume) == 0 && length(aws_iam_role.dlm) == 0
    error_message = "No snapshot resources may exist when both inputs are off."
  }
}

run "snapshot_retention_rejects_zero" {
  command = plan

  variables {
    data_volume_creation_enabled         = true
    data_volume_snapshot_retention_count = 0
  }

  expect_failures = [var.data_volume_snapshot_retention_count]
}

run "snapshot_retention_rejects_more_than_1000" {
  command = plan

  variables {
    data_volume_creation_enabled         = true
    data_volume_snapshot_retention_count = 1001
  }

  expect_failures = [var.data_volume_snapshot_retention_count]
}

run "snapshot_retention_rejects_fractions" {
  command = plan

  variables {
    data_volume_creation_enabled         = true
    data_volume_snapshot_retention_count = 2.5
  }

  expect_failures = [var.data_volume_snapshot_retention_count]
}

################################################################################
# Boot-time data volume mount
################################################################################

run "user_data_labels_new_volumes_and_remounts_existing_ones" {
  command = plan

  variables {
    data_volume_creation_enabled = true
    data_volume_mount_path       = "/var/lib/app"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "mkfs -t xfs -L \"$RAVION_DATA_LABEL\" \"$disk\"") && strcontains(base64decode(aws_launch_template.app.user_data), "RAVION_DATA_LABEL=\"ravion-data\"")
    error_message = "New data volumes must be formatted with the ravion-data label."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "RAVION_DATA_MOUNT_PATH=\"/var/lib/app\"") && strcontains(base64decode(aws_launch_template.app.user_data), "\nravion_mount_data_volume || true\n")
    error_message = "Boot must mount the data volume at the configured path on every run, not only after formatting."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "defaults,nofail 0 2") && strcontains(base64decode(aws_launch_template.app.user_data), "UUID=$uuid")
    error_message = "The data volume must be recorded in fstab by UUID with nofail."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "RAVION_DATA_DEVICE_LINKS:-/dev/xvdf /dev/sdf") && contains([for mapping in aws_launch_template.app.block_device_mappings : mapping.device_name], "/dev/xvdf")
    error_message = "Discovery must look for the device name the launch template attaches the data volume under."
  }

  assert {
    condition     = !strcontains(base64decode(aws_launch_template.app.user_data), "mkfs -t xfs \"$DATA_DEVICE\"")
    error_message = "The old format-first-blank-disk logic must be gone."
  }

  assert {
    condition     = length(base64decode(aws_launch_template.app.user_data)) < 16384
    error_message = "User data must stay under the 16 KB EC2 limit."
  }
}

run "user_data_skips_data_volume_logic_without_one" {
  command = plan

  variables {
    data_volume_creation_enabled = false
  }

  assert {
    condition     = !strcontains(base64decode(aws_launch_template.app.user_data), "ravion_mount_data_volume") && !strcontains(base64decode(aws_launch_template.app.user_data), "mkfs")
    error_message = "Services without a data volume must not run any data volume logic."
  }
}

run "user_data_efs_fstab_entry_is_idempotent" {
  command = plan

  variables {
    efs_enabled        = true
    efs_file_system_id = "fs-12345678"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "awk -v path=\"/mnt/efs\"") && strcontains(base64decode(aws_launch_template.app.user_data), "fs-12345678 /mnt/efs efs _netdev,tls 0 0")
    error_message = "The EFS fstab entry must only be added when the path has none yet."
  }
}

################################################################################
# Deploy storage guard
################################################################################

run "container_deploy_guards_the_data_volume_before_stopping_the_app" {
  command = plan

  variables {
    runtime                         = "container"
    data_volume_creation_enabled    = true
    app_port                        = 3000
    deploy_health_check_path        = "/health"
    load_balancer_security_group_id = "sg-87654321"
    load_balancer_attachment = {
      creation_enabled = true
      target_group     = { port = 3000 }
      listener_rules   = []
    }
  }

  assert {
    condition     = strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "Data volume not mounted at /data; refusing to start the app so it does not write to the root disk.")
    error_message = "Container deploys must refuse to run without the data volume."
  }

  assert {
    condition     = strcontains(split("Deregistering", yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0])[0], "if ! mountpoint -q \"/data\"; then")
    error_message = "The guard must run before the instance is drained from the target group."
  }

  assert {
    condition     = strcontains(split("supervisorctl -c /etc/supervisord.conf stop", yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0])[0], "\nravion_mount_data_volume || true\n")
    error_message = "The guard must try to mount the data volume before the old container is stopped."
  }

  assert {
    condition     = strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "exit 1") && !strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "mount -a -t efs")
    error_message = "The data volume guard must fail the deploy and must not check EFS when EFS is off."
  }

  assert {
    condition     = !strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "mkfs")
    error_message = "Deploys must never format a disk."
  }
}

run "manual_deploy_guards_data_volume_and_efs_before_stopping_the_app" {
  command = plan

  variables {
    runtime                      = "manual"
    manual_start_command         = "./bin/server"
    data_volume_creation_enabled = true
    efs_enabled                  = true
    efs_file_system_id           = "fs-12345678"
    efs_mount_path               = "/mnt/shared"
  }

  assert {
    condition = alltrue([
      for text in [
        "Data volume not mounted at /data; refusing to start the app so it does not write to the root disk.",
        "\nravion_mount_data_volume || true\n",
        "mount -a -t efs || true",
        "if ! mountpoint -q \"/mnt/shared\"; then",
        "EFS file system not mounted at /mnt/shared; refusing to start the app so it does not write to the root disk.",
      ] :
      strcontains(split("supervisorctl -c /etc/supervisord.conf stop", yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0])[0], text)
    ])
    error_message = "Manual deploys must check the data volume and EFS before stopping the running app."
  }

  assert {
    condition     = strcontains(split("{{ commands }}", yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0])[0], "refusing to start the app")
    error_message = "The guard must run before the user's deploy commands."
  }

  assert {
    condition     = !strcontains(aws_ssm_document.deploy.content, "mkfs")
    error_message = "Manual deploys must never format a disk."
  }
}

run "container_deploy_guards_efs_only" {
  command = plan

  variables {
    runtime                      = "container"
    data_volume_creation_enabled = false
    efs_enabled                  = true
    efs_file_system_id           = "fs-12345678"
  }

  assert {
    condition     = strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "EFS file system not mounted at /mnt/efs; refusing to start the app")
    error_message = "Container deploys must refuse to run without EFS when it is enabled."
  }

  assert {
    condition     = !strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "ravion_mount_data_volume")
    error_message = "Without a data volume the guard must not look for one."
  }
}

run "deploys_have_no_guard_without_extra_storage" {
  command = plan

  variables {
    runtime                      = "container"
    data_volume_creation_enabled = false
  }

  assert {
    condition     = !strcontains(aws_ssm_document.deploy.content, "refusing to start the app") && !strcontains(aws_ssm_document.deploy.content, "ravion_mount_data_volume") && !strcontains(aws_ssm_document.deploy.content, "cloud-init status --wait")
    error_message = "Services without a data volume or EFS must deploy without a storage guard."
  }
}

run "manual_deploys_have_no_guard_without_extra_storage" {
  command = plan

  variables {
    runtime                      = "manual"
    manual_start_command         = "./bin/server"
    data_volume_creation_enabled = false
  }

  assert {
    condition     = !strcontains(aws_ssm_document.deploy.content, "refusing to start the app") && !strcontains(aws_ssm_document.deploy.content, "ravion_mount_data_volume")
    error_message = "Manual services without a data volume or EFS must deploy without a storage guard."
  }
}

run "rejects_root_data_volume_mount_path" {
  command = plan

  variables {
    data_volume_mount_path = "/"
  }

  expect_failures = [var.data_volume_mount_path]
}

run "rejects_root_efs_mount_path" {
  command = plan

  variables {
    efs_enabled        = true
    efs_file_system_id = "fs-12345678"
    efs_mount_path     = "/"
  }

  expect_failures = [var.efs_mount_path]
}

run "rejects_same_data_volume_and_efs_paths" {
  command = plan

  variables {
    efs_enabled            = true
    efs_file_system_id     = "fs-12345678"
    data_volume_mount_path = "/data"
    efs_mount_path         = "/data/"
  }

  expect_failures = [aws_launch_template.app]
}

run "guard_checks_what_is_mounted" {
  command = plan

  variables {
    runtime            = "container"
    efs_enabled        = true
    efs_file_system_id = "fs-12345678"
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "is on the root disk") && strcontains(aws_ssm_document.deploy.content, "not EFS; refusing to start the app")
    error_message = "The guard must check that the data path is not on the root disk and that the EFS path holds EFS."
  }
}
