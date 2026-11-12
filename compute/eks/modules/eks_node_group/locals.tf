locals {
  region    = data.aws_region.current.region
  partition = var.partition != null ? var.partition : data.aws_partition.current.partition

  ami_kubernetes_version = var.kubernetes_version != null ? var.kubernetes_version : (
    local.track_ami_release ? data.aws_eks_cluster.current[0].version : ""
  )
  ami_release_parameters = {
    AL2_x86_64                 = "/aws/service/eks/optimized-ami/%s/amazon-linux-2/recommended/release_version"
    AL2_x86_64_GPU             = "/aws/service/eks/optimized-ami/%s/amazon-linux-2-gpu/recommended/release_version"
    AL2_ARM_64                 = "/aws/service/eks/optimized-ami/%s/amazon-linux-2-arm64/recommended/release_version"
    AL2023_x86_64_STANDARD     = "/aws/service/eks/optimized-ami/%s/amazon-linux-2023/x86_64/standard/recommended/release_version"
    AL2023_ARM_64_STANDARD     = "/aws/service/eks/optimized-ami/%s/amazon-linux-2023/arm64/standard/recommended/release_version"
    AL2023_x86_64_NEURON       = "/aws/service/eks/optimized-ami/%s/amazon-linux-2023/x86_64/neuron/recommended/release_version"
    AL2023_x86_64_NVIDIA       = "/aws/service/eks/optimized-ami/%s/amazon-linux-2023/x86_64/nvidia/recommended/release_version"
    AL2023_ARM_64_NVIDIA       = "/aws/service/eks/optimized-ami/%s/amazon-linux-2023/arm64/nvidia/recommended/release_version"
    BOTTLEROCKET_x86_64        = "/aws/service/bottlerocket/aws-k8s-%s/x86_64/latest/image_version"
    BOTTLEROCKET_ARM_64        = "/aws/service/bottlerocket/aws-k8s-%s/arm64/latest/image_version"
    BOTTLEROCKET_x86_64_NVIDIA = "/aws/service/bottlerocket/aws-k8s-%s-nvidia/x86_64/latest/image_version"
    BOTTLEROCKET_ARM_64_NVIDIA = "/aws/service/bottlerocket/aws-k8s-%s-nvidia/arm64/latest/image_version"
  }
  track_ami_release = contains(keys(local.ami_release_parameters), var.ami_type)
}

################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks/modules/eks_node_group"
  }

  tags = merge(local.default_tags, var.tags)

  create_node_role = var.node_role_arn == null
  node_role_arn    = local.create_node_role ? module.node_role[0].role_arn : var.node_role_arn

  # EKS-managed launch templates (the default when none is supplied) cannot
  # encrypt the root volume or lower the IMDS hop limit, and both are on by
  # default here, so in practice a launch template is always created. The
  # conditions stay so a caller who turns both off still gets the lean path.
  create_launch_template = (
    var.user_data != null
    || var.disk_size != null
    || var.disk_type != null
    || var.disk_iops != null
    || var.disk_throughput != null
    || var.ebs_encryption_enabled
    || var.ebs_kms_key_arn != null
    || length(var.security_group_ids) > 0
    || var.detailed_monitoring_enabled
    || var.metadata_http_tokens != "required"
    || var.metadata_http_put_response_hop_limit != 2
  )

  # The root device differs by AMI family; the block device mapping below has
  # to name it exactly or EKS attaches a second, unused volume.
  root_device_name = startswith(var.ami_type, "WINDOWS") ? "/dev/sda1" : "/dev/xvda"

  configure_root_volume = (
    var.disk_size != null
    || var.disk_type != null
    || var.ebs_encryption_enabled
    || var.ebs_kms_key_arn != null
  )
}
