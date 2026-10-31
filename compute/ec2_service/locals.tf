################################################################################
# Local Values
################################################################################

locals {
  # Default tags for all resources
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/ec2_service"
  }

  tags = merge(local.default_tags, var.tags)

  region = coalesce(var.region, data.aws_region.current.region)

  container_runtime = var.runtime == "container"

  load_balancer_creation_enabled = var.load_balancer_attachment != null ? var.load_balancer_attachment.creation_enabled : false

  cpu_architecture = var.ami_id == null ? (
    contains(data.aws_ec2_instance_type.selected[0].supported_architectures, "arm64") ? "arm64" : "x86_64"
  ) : null

  ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.al2023_ami[0].value

  log_group_name = "/ravion/ec2/${var.name}"

  # App layout shared by both deploy modes. Each deployment gets its own
  # app log file and CloudWatch stream under the service log group.
  env_file_path                 = "/etc/ravion/${var.name}.env"
  log_directory                 = "/var/log/ravion/${var.name}"
  supervisor_program            = "ravion-${var.name}"
  supervisor_conf               = "/etc/supervisord.d/${var.name}.ini"
  app_runner_path               = "/usr/local/bin/ravion-${var.name}-run"
  image_ref_path                = "/etc/ravion/${var.name}.image"
  start_command_path            = "/etc/ravion/${var.name}.start-command"
  source_working_directory_path = "/etc/ravion/${var.name}.source-working-directory"

  supervisor_install_script = templatefile("${path.module}/templates/install_supervisor.sh.tpl", {})

  # The launch template attaches the data volume under this device name. On
  # Nitro instances the disk appears as NVMe and Amazon Linux links it back
  # to the requested name; the scripts check both the xvd and sd spellings.
  data_volume_device_name = "/dev/xvdf"
  data_volume_label       = "ravion-data"

  # Data volume discovery and mount, shared by boot and the deploy guard.
  data_volume_mount_script = templatefile("${path.module}/templates/data_volume_mount.sh.tpl", {
    data_volume_device_links = "${local.data_volume_device_name} ${replace(local.data_volume_device_name, "/dev/xvd", "/dev/sd")}"
    data_volume_label        = local.data_volume_label
    data_volume_mount_path   = var.data_volume_mount_path
  })

  # Fail-closed storage check run by both deploy modes before the running
  # app is stopped. Empty when the service has no data volume or EFS.
  storage_guard_script = templatefile("${path.module}/templates/ensure_storage.sh.tpl", {
    data_volume_enabled      = var.data_volume_creation_enabled
    data_volume_mount_path   = var.data_volume_mount_path
    data_volume_mount_script = local.data_volume_mount_script
    efs_enabled              = var.efs_enabled
    efs_mount_path           = var.efs_mount_path
  })

  deployment_log_script = templatefile("${path.module}/templates/configure_deployment_logs.sh.tpl", {
    log_directory  = local.log_directory
    log_group_name = local.log_group_name
  })

  supervisor_program_script = templatefile("${path.module}/templates/configure_supervisor_program.sh.tpl", {
    app_runner_path           = local.app_runner_path
    log_rotation_backup_count = var.log_rotation_backup_count
    log_rotation_max_size_mb  = var.log_rotation_max_size_mb
    supervisor_conf           = local.supervisor_conf
    supervisor_program        = local.supervisor_program
  })

  # Env-file builder script shared by instance boot and both deploy modes.
  # Plain values are Terraform-rendered (like
  # an ECS task definition's environment); secrets are fetched on the
  # instance so their values stay out of state and the SSM document.
  env_file_script = templatefile("${path.module}/templates/env_file.sh.tpl", {
    environment_variables = var.environment_variables
    secrets               = var.secrets
    app_port              = var.app_port
    env_file_path         = local.env_file_path
    region                = local.region
  })

  manual_deploy_prelude = templatefile("${path.module}/templates/deploy_manual_before.sh.tpl", {
    deployment_log_script = local.deployment_log_script
    env_file_path         = local.env_file_path
    env_file_script       = local.env_file_script
    git_source_checkout_script = templatefile("${path.module}/templates/checkout_git_source.sh.tpl", {
      name                          = var.name
      region                        = local.region
      source_working_directory_path = local.source_working_directory_path
    })
    name                      = var.name
    storage_guard_script      = local.storage_guard_script
    supervisor_install_script = local.supervisor_install_script
    supervisor_program        = local.supervisor_program
  })

  manual_deploy_postlude = templatefile("${path.module}/templates/deploy_manual_after.sh.tpl", {
    app_runner_path               = local.app_runner_path
    env_file_path                 = local.env_file_path
    manual_start_command_base64   = base64encode(var.manual_start_command != null ? var.manual_start_command : "")
    start_command_path            = local.start_command_path
    source_working_directory_path = local.source_working_directory_path
    supervisor_program            = local.supervisor_program
    supervisor_program_script     = local.supervisor_program_script
  })

  deploy_script = local.container_runtime ? templatefile("${path.module}/templates/deploy_container.sh.tpl", {
    name                        = var.name
    region                      = local.region
    app_port                    = var.app_port
    start_command               = var.container_start_command != null ? var.container_start_command : ""
    deploy_health_check_path    = var.deploy_health_check_path != null ? var.deploy_health_check_path : ""
    env_file_script             = local.env_file_script
    env_file_path               = local.env_file_path
    app_runner_path             = local.app_runner_path
    deployment_log_script       = local.deployment_log_script
    image_ref_path              = local.image_ref_path
    supervisor_conf             = local.supervisor_conf
    supervisor_install_script   = local.supervisor_install_script
    supervisor_program          = local.supervisor_program
    supervisor_program_script   = local.supervisor_program_script
    target_group_arn            = local.load_balancer_creation_enabled ? aws_lb_target_group.app[0].arn : ""
    data_volume_mount_path      = var.data_volume_creation_enabled ? var.data_volume_mount_path : ""
    efs_mount_path              = var.efs_enabled ? var.efs_mount_path : ""
    docker_socket_mount_enabled = var.docker_socket_mount_enabled
    storage_guard_script        = local.storage_guard_script
  }) : null

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    name                         = var.name
    region                       = local.region
    env_file_script              = local.env_file_script
    env_file_path                = local.env_file_path
    supervisor_install_script    = local.supervisor_install_script
    data_volume_creation_enabled = var.data_volume_creation_enabled
    data_volume_mount_path       = var.data_volume_mount_path
    data_volume_mount_script     = local.data_volume_mount_script
    data_volume_format_script    = templatefile("${path.module}/templates/data_volume_format.sh.tpl", {})
    efs_enabled                  = var.efs_enabled
    efs_file_system_id           = var.efs_file_system_id != null ? var.efs_file_system_id : ""
    efs_access_point_id          = var.efs_access_point_id != null ? var.efs_access_point_id : ""
    efs_mount_path               = var.efs_mount_path
    additional_user_data         = var.additional_user_data
  }))
}
