################################################################################
# General
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the existing EKS cluster to install add-ons onto."

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9-_]{0,99}$", var.cluster_name))
    error_message = "The cluster_name must be 1-100 characters: start with alphanumeric, then alphanumerics, hyphens, or underscores (EKS cluster name constraints)."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags applied to EC2 instances launched by the default Karpenter NodePool."
  default     = {}
}

################################################################################
# Zone-local routing
################################################################################

variable "topology_aware_routing_enabled" {
  type        = bool
  description = "Patch the kube-dns Service with trafficDistribution: PreferClose so DNS lookups stay in the caller's availability zone; the compute/eks composite spreads the CoreDNS pods to match. Disabling destroys the patch release, whose pre-delete hook clears the field again. Needs Kubernetes 1.31+; older API servers ignore the field."
  default     = true
  nullable    = false
}

variable "kubectl_image" {
  type        = string
  description = "kubectl image (repository:tag) the kube-dns patch Jobs run. Pinned; override for clusters that must pull from a private mirror."
  default     = "registry.k8s.io/kubectl:v1.33.12"
  nullable    = false

  validation {
    condition     = can(regex("^(.*):([^:/]+)$", var.kubectl_image))
    error_message = "kubectl_image must be a repository:tag reference."
  }
}

################################################################################
# AWS Load Balancer Controller
################################################################################

variable "aws_load_balancer_controller_enabled" {
  type        = bool
  description = "Install the AWS Load Balancer Controller even when no shared load balancer is enabled, e.g. to provision ALBs/NLBs directly from Ingress and LoadBalancer resources. The controller is installed automatically whenever any shared load balancer is enabled, since workload target registration (TargetGroupBinding) depends on it."
  default     = false
}

variable "aws_load_balancer_controller_chart_version" {
  type        = string
  description = "Version of the aws-load-balancer-controller Helm chart to install."
  default     = "1.14.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.aws_load_balancer_controller_chart_version))
    error_message = "The aws_load_balancer_controller_chart_version must be a semantic version like '1.14.0' (no leading 'v')."
  }
}

variable "aws_load_balancer_controller_namespace" {
  type        = string
  description = "Namespace the controller is installed into. Must match the Pod Identity association created by the compute/eks stack."
  default     = "kube-system"
}

variable "aws_load_balancer_controller_service_account" {
  type        = string
  description = "Service account name for the controller. Must match the Pod Identity association created by the compute/eks stack."
  default     = "aws-load-balancer-controller"
}

variable "aws_load_balancer_controller_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the aws-load-balancer-controller chart values (later entries win)."
  default     = []
}

################################################################################
# EBS CSI Driver
################################################################################

variable "ebs_csi_driver_enabled" {
  type        = bool
  description = "Install the aws-ebs-csi-driver add-on and create its Pod Identity role so workloads can use EBS-backed persistent volumes."
  default     = false
}

variable "ebs_csi_addon_version" {
  type        = string
  description = "Pinned version for the aws-ebs-csi-driver add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "ebs_csi_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for aws-ebs-csi-driver."
  default     = null
}

################################################################################
# CloudWatch Observability (Container Insights)
#
# CloudWatch is a provider in logs_providers / metrics_providers now, not a
# section of its own. The variables below are what the provider reads; see
# observability.tf for the selection logic.
################################################################################

variable "cloudwatch_observability_addon_version" {
  type        = string
  description = "Pinned version for the amazon-cloudwatch-observability add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "cloudwatch_observability_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for amazon-cloudwatch-observability."
  default     = null
}

################################################################################
# External Secrets Operator
################################################################################

variable "eso_enabled" {
  type        = bool
  description = "Install the External Secrets Operator, its Pod Identity role, and the Ravion ClusterSecretStores. Workloads then reference Secrets Manager secrets and SSM parameters by ARN and ESO materializes them into Kubernetes Secrets, so secret values never pass through Ravion, Helm values, or release history."
  default     = true
}

variable "eso_chart_version" {
  type        = string
  description = "Version of the external-secrets Helm chart to install."
  default     = "2.8.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.eso_chart_version))
    error_message = "The eso_chart_version must be a semantic version like '2.8.0' (no leading 'v')."
  }
}

variable "eso_namespace" {
  type        = string
  description = "Kubernetes namespace the External Secrets Operator is installed into. Created if it does not exist."
  default     = "external-secrets"
  nullable    = false
}

variable "eso_service_account" {
  type        = string
  description = "Service account name for the External Secrets Operator controller. Must match the chart's service account, since the Pod Identity association binds credentials to this name."
  default     = "external-secrets"
  nullable    = false
}

variable "eso_secret_and_parameter_arns" {
  type        = list(string)
  description = "Secrets Manager secret and SSM parameter ARNs (wildcards allowed) the operator may read. When empty, the role can read every secret and parameter in this account and region. Set this to scope the role down, or to grant access to other regions and accounts."
  default     = []

  validation {
    condition     = alltrue([for arn in var.eso_secret_and_parameter_arns : can(regex("^arn:[^:]*:(secretsmanager|ssm):", arn))])
    error_message = "All eso_secret_and_parameter_arns must be Secrets Manager or SSM ARNs, e.g. 'arn:aws:secretsmanager:us-east-2:111122223333:secret:prod/*' or 'arn:aws:ssm:us-east-2:111122223333:parameter/prod/*'."
  }
}

variable "eso_kms_key_arns" {
  type        = list(string)
  description = "Customer-managed KMS key ARNs the operator may decrypt with. Only needed for secrets or parameters encrypted with a customer-managed key; the AWS-managed aws/secretsmanager and aws/ssm keys need no explicit grant."
  default     = []

  validation {
    condition     = alltrue([for arn in var.eso_kms_key_arns : can(regex("^arn:[^:]*:kms:", arn))])
    error_message = "All eso_kms_key_arns must be valid KMS key ARNs."
  }
}

variable "eso_cluster_secret_stores_creation_enabled" {
  type        = bool
  description = "Create the Ravion ClusterSecretStores. Disable to manage SecretStore resources yourself; workload charts then need their own store reference."
  default     = true
}

variable "eso_secrets_manager_store_name" {
  type        = string
  description = "Name of the cluster-scoped AWS Secrets Manager store. This is the store name Ravion app charts default to."
  default     = "ravion-aws"
  nullable    = false
}

variable "eso_parameter_store_store_name" {
  type        = string
  description = "Name of the cluster-scoped AWS SSM Parameter Store store. A separate store is required because ESO's AWS provider takes a single service per store."
  default     = "ravion-aws-parameter-store"
  nullable    = false
}

variable "eso_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the external-secrets chart values, after the values this module derives (CRD install, service account). Later entries win."
  default     = []
}

################################################################################
# Karpenter
################################################################################

variable "karpenter_enabled" {
  type        = bool
  description = "Install Karpenter end to end: controller and node IAM roles, Pod Identity association, instance profile, interruption queue, EventBridge rules, the controller Helm charts, and (optionally) a default NodePool."
  default     = true
}

variable "ravion_runner_role_arn" {
  type        = string
  description = "IAM role assumed by `aws eks get-token` to authenticate to the Kubernetes API (ravion_runner_role_arn output of the compute/eks stack). When null, the identity running Terraform is used directly and must already have cluster access."
  default     = null

  validation {
    condition     = var.ravion_runner_role_arn == null || can(regex("^arn:aws", var.ravion_runner_role_arn))
    error_message = "The ravion_runner_role_arn must be an IAM role ARN starting with 'arn:aws'."
  }
}

variable "karpenter_controller_namespace" {
  type        = string
  description = "Kubernetes namespace where the Karpenter controller is installed."
  default     = "kube-system"
  nullable    = false
}

variable "karpenter_controller_service_account" {
  type        = string
  description = "Kubernetes service account name for the Karpenter controller."
  default     = "karpenter"
  nullable    = false
}

variable "karpenter_node_role_additional_managed_policy_arns" {
  type        = list(string)
  description = "Extra managed policy ARNs to attach to the Karpenter-launched node role."
  default     = []
}

variable "karpenter_chart_version" {
  type        = string
  description = "Version of the Karpenter Helm chart (and karpenter-crd chart) to install."
  default     = "1.14.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.karpenter_chart_version))
    error_message = "The karpenter_chart_version must be a semantic version like '1.14.0' (no leading 'v')."
  }
}

variable "karpenter_interruption_queue_name" {
  type        = string
  description = "Name for the SQS interruption queue. When null, defaults to 'karpenter-<cluster_name>'."
  default     = null
}

variable "karpenter_interruption_queue_message_retention_seconds" {
  type        = number
  description = "Message retention for the Karpenter interruption queue."
  default     = 300
}

variable "karpenter_helm_values" {
  type        = list(string)
  description = "Additional YAML documents merged into the Karpenter Helm chart values, after the values this module derives (cluster name, interruption queue, service account). Later entries win."
  default     = []
}

################################################################################
# Default NodePool
################################################################################

variable "karpenter_default_node_pool_creation_enabled" {
  type        = bool
  description = "Create a general-purpose default NodePool and EC2NodeClass so Karpenter can provision nodes out of the box. Disable to manage NodePools yourself."
  default     = true
}

variable "node_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs (node_subnet_ids output of the compute/eks stack). Used by the default Karpenter NodePool to launch nodes and by internal load balancers. Required when Karpenter's default NodePool, the private ALB, or the private NLB is enabled."
  default     = null

  validation {
    condition     = var.node_subnet_ids == null || alltrue([for s in coalesce(var.node_subnet_ids, []) : can(regex("^subnet-", s))])
    error_message = "All node_subnet_ids must start with 'subnet-'."
  }

  validation {
    condition     = !(var.karpenter_enabled && var.karpenter_default_node_pool_creation_enabled) || (var.node_subnet_ids != null && length(coalesce(var.node_subnet_ids, [])) >= 1)
    error_message = "node_subnet_ids is required when karpenter_enabled and karpenter_default_node_pool_creation_enabled are true."
  }

  validation {
    condition     = !(var.private_alb_creation_enabled || var.private_nlb_creation_enabled) || (var.node_subnet_ids != null && length(coalesce(var.node_subnet_ids, [])) >= 1)
    error_message = "node_subnet_ids is required when private_alb_creation_enabled or private_nlb_creation_enabled is true."
  }
}

variable "cluster_security_group_id" {
  type        = string
  description = "EKS-managed cluster security group (cluster_security_group_id output of the compute/eks stack). Attached to Karpenter-launched nodes and opened to shared load balancers so they can reach pods. Required when Karpenter's default NodePool or any shared load balancer is enabled."
  default     = null

  validation {
    condition     = var.cluster_security_group_id == null || can(regex("^sg-", var.cluster_security_group_id))
    error_message = "The cluster_security_group_id must be a valid security group ID starting with 'sg-'."
  }

  validation {
    condition     = !(var.karpenter_enabled && var.karpenter_default_node_pool_creation_enabled) || var.cluster_security_group_id != null
    error_message = "cluster_security_group_id is required when karpenter_enabled and karpenter_default_node_pool_creation_enabled are true."
  }

  validation {
    condition     = !(var.public_alb_creation_enabled || var.private_alb_creation_enabled || var.public_nlb_creation_enabled || var.private_nlb_creation_enabled) || var.cluster_security_group_id != null
    error_message = "cluster_security_group_id is required when any shared load balancer is enabled."
  }
}

################################################################################
# Shared Load Balancers
################################################################################

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for internet-facing load balancers (public_subnet_ids output of the compute/eks stack). Required when the public ALB or public NLB is enabled."
  default     = []

  validation {
    condition     = alltrue([for s in var.public_subnet_ids : can(regex("^subnet-", s))])
    error_message = "All public_subnet_ids must start with 'subnet-'."
  }

  validation {
    condition     = !(var.public_alb_creation_enabled || var.public_nlb_creation_enabled) || length(var.public_subnet_ids) >= 1
    error_message = "public_subnet_ids is required when public_alb_creation_enabled or public_nlb_creation_enabled is true."
  }
}

variable "load_balancer_deletion_protection_enabled" {
  type        = bool
  description = "Enable deletion protection on the shared load balancers."
  default     = false
}

################################################################################
# Public ALB
################################################################################

variable "public_alb_creation_enabled" {
  type        = bool
  description = "Create a shared public (internet-facing) Application Load Balancer that workloads attach to via TargetGroupBinding."
  default     = false
}

variable "public_alb_https_enabled" {
  type        = bool
  description = "Enable HTTPS listener on the public ALB."
  default     = false
}

variable "public_alb_certificate_arns" {
  type        = list(string)
  description = "ACM certificate ARNs for the public ALB HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI."
  default     = []

  validation {
    condition     = alltrue([for arn in var.public_alb_certificate_arns : can(regex("^arn:aws:acm:", arn))])
    error_message = "All public_alb_certificate_arns must be valid ACM certificate ARNs."
  }
}

variable "public_alb_ssl_policy" {
  type        = string
  description = "The SSL policy for the public ALB HTTPS listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "public_alb_idle_timeout" {
  type        = number
  description = "The idle timeout for the public ALB in seconds."
  default     = 60

  validation {
    condition     = var.public_alb_idle_timeout >= 1 && var.public_alb_idle_timeout <= 4000
    error_message = "The public_alb_idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "public_alb_ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to access the public ALB."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.public_alb_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All public_alb_ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "public_alb_ingress_ipv6_cidr_blocks" {
  type        = list(string)
  description = "IPv6 CIDR blocks allowed to access the public ALB."
  default     = ["::/0"]
}

variable "public_alb_ingress_security_group_ids" {
  type        = list(string)
  description = "Security group IDs whose members are allowed to access the public ALB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.public_alb_ingress_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All public_alb_ingress_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "public_alb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the public ALB."
  default     = false
}

variable "public_alb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for public ALB access logs."
  default     = null

  validation {
    condition     = var.public_alb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.public_alb_access_logs_bucket_arn))
    error_message = "The public_alb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "public_alb_web_acl_arn" {
  type        = string
  description = "The ARN of a WAFv2 Web ACL to associate with the public ALB."
  default     = null

  validation {
    condition     = var.public_alb_web_acl_arn == null || can(regex("^arn:aws:wafv2:", var.public_alb_web_acl_arn))
    error_message = "The public_alb_web_acl_arn must be a valid WAFv2 Web ACL ARN."
  }
}

################################################################################
# Private ALB
################################################################################

variable "private_alb_creation_enabled" {
  type        = bool
  description = "Create a shared private (internal) Application Load Balancer that workloads attach to via TargetGroupBinding."
  default     = false
}

variable "private_alb_https_enabled" {
  type        = bool
  description = "Enable HTTPS listener on the private ALB."
  default     = false
}

variable "private_alb_certificate_arns" {
  type        = list(string)
  description = "ACM certificate ARNs for the private ALB HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI."
  default     = []

  validation {
    condition     = alltrue([for arn in var.private_alb_certificate_arns : can(regex("^arn:aws:acm:", arn))])
    error_message = "All private_alb_certificate_arns must be valid ACM certificate ARNs."
  }
}

variable "private_alb_ssl_policy" {
  type        = string
  description = "The SSL policy for the private ALB HTTPS listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "private_alb_idle_timeout" {
  type        = number
  description = "The idle timeout for the private ALB in seconds."
  default     = 60

  validation {
    condition     = var.private_alb_idle_timeout >= 1 && var.private_alb_idle_timeout <= 4000
    error_message = "The private_alb_idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "private_alb_ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to access the private ALB."
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.private_alb_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All private_alb_ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "private_alb_ingress_ipv6_cidr_blocks" {
  type        = list(string)
  description = "IPv6 CIDR blocks allowed to access the private ALB. Defaults to no IPv6 ingress; RFC1918 has no IPv6 equivalent."
  default     = []
}

variable "private_alb_ingress_security_group_ids" {
  type        = list(string)
  description = "Security group IDs whose members are allowed to access the private ALB. Useful for sources without static CIDRs, such as CloudFront VPC origins."
  default     = []

  validation {
    condition     = alltrue([for sg in var.private_alb_ingress_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All private_alb_ingress_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "private_alb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the private ALB."
  default     = false
}

variable "private_alb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for private ALB access logs."
  default     = null

  validation {
    condition     = var.private_alb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.private_alb_access_logs_bucket_arn))
    error_message = "The private_alb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

################################################################################
# Public NLB
################################################################################

variable "public_nlb_creation_enabled" {
  type        = bool
  description = "Create a shared public (internet-facing) Network Load Balancer that workloads attach to via TargetGroupBinding."
  default     = false
}

variable "public_nlb_cross_zone_load_balancing_enabled" {
  type        = bool
  description = "Enable cross-zone load balancing for the public NLB."
  default     = false
}

variable "public_nlb_security_group_ids" {
  type        = list(string)
  description = "A list of additional security group IDs to attach to the public NLB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.public_nlb_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All public_nlb_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "public_nlb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the public NLB."
  default     = false
}

variable "public_nlb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for public NLB access logs."
  default     = null

  validation {
    condition     = var.public_nlb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.public_nlb_access_logs_bucket_arn))
    error_message = "The public_nlb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "public_nlb_elastic_ips_enabled" {
  type        = bool
  description = "Enable static IP addresses for the public NLB using Elastic IPs."
  default     = false
}

variable "public_nlb_elastic_ip_allocation_ids" {
  type        = list(string)
  description = "A list of Elastic IP allocation IDs for the public NLB, one per subnet."
  default     = []

  validation {
    condition     = alltrue([for eip in var.public_nlb_elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])
    error_message = "All public_nlb_elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }
}

################################################################################
# Private NLB
################################################################################

variable "private_nlb_creation_enabled" {
  type        = bool
  description = "Create a shared private (internal) Network Load Balancer that workloads attach to via TargetGroupBinding."
  default     = false
}

variable "private_nlb_cross_zone_load_balancing_enabled" {
  type        = bool
  description = "Enable cross-zone load balancing for the private NLB."
  default     = false
}

variable "private_nlb_security_group_ids" {
  type        = list(string)
  description = "A list of additional security group IDs to attach to the private NLB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.private_nlb_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All private_nlb_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "private_nlb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the private NLB."
  default     = false
}

variable "private_nlb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for private NLB access logs."
  default     = null

  validation {
    condition     = var.private_nlb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.private_nlb_access_logs_bucket_arn))
    error_message = "The private_nlb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "private_nlb_elastic_ips_enabled" {
  type        = bool
  description = "Enable static IP addresses for the private NLB using Elastic IPs."
  default     = false
}

variable "private_nlb_elastic_ip_allocation_ids" {
  type        = list(string)
  description = "A list of Elastic IP allocation IDs for the private NLB, one per subnet."
  default     = []

  validation {
    condition     = alltrue([for eip in var.private_nlb_elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])
    error_message = "All private_nlb_elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }
}

variable "karpenter_default_node_pool" {
  type = object({
    capacity_types      = optional(list(string), ["on-demand", "spot"])
    instance_categories = optional(list(string), ["c", "m", "r"])
    architectures       = optional(list(string), ["amd64"])
    cpu_limit           = optional(number, 100)
    expire_after        = optional(string, "720h")
  })
  description = "Settings for the default NodePool: allowed capacity types (on-demand/spot), EC2 instance categories, CPU architectures, total vCPU limit, and node expiry."
  default     = {}

  validation {
    condition     = alltrue([for t in var.karpenter_default_node_pool.capacity_types : contains(["on-demand", "spot"], t)])
    error_message = "The karpenter_default_node_pool.capacity_types entries must be 'on-demand' or 'spot'."
  }

  validation {
    condition     = alltrue([for a in var.karpenter_default_node_pool.architectures : contains(["amd64", "arm64"], a)])
    error_message = "The karpenter_default_node_pool.architectures entries must be 'amd64' or 'arm64'."
  }
}

################################################################################
# Ravion Operator
################################################################################

variable "ravion_operator_enabled" {
  type        = bool
  description = "Install the Ravion Operator: mint the cluster's WorkOS M2M credential through the Ravion provider, write it into a Kubernetes Secret (and mirror it into AWS Secrets Manager), and install the agent's Helm chart. The provider authenticates with RAVION_BASE_URL/RAVION_API_KEY from the environment, which a Ravion pipeline injects — there is no API token input. Ravion Operator dials Ravion outbound over a single WebSocket and is read-only unless ravion_operator_deploy_enabled, ravion_operator_exec_enabled, or the equivalent chart values are turned on."
  default     = false
  nullable    = false
}

variable "ravion_operator_endpoint" {
  type        = string
  description = "WebSocket endpoint the agent dials. Outbound 443 only, and the single destination a customer's egress policy has to allow. A domain of its own on purpose, so that address need not change when Ravion moves agent connections into their own deployment. Override for staging, a self-hosted control plane, or a local gateway over ws://."
  default     = "wss://websockets.ravion.com/operator/v1/connect"
  nullable    = false

  validation {
    condition     = can(regex("^wss?://", var.ravion_operator_endpoint))
    error_message = "The ravion_operator_endpoint must be a WebSocket URL starting with 'wss://' (or 'ws://' for local testing)."
  }
}

variable "ravion_operator_chart_source" {
  type        = string
  description = "Where the agent's Helm chart comes from. An 'oci://' reference is split into repository and chart name; anything else is treated as a filesystem path to a chart directory, which is how the chart is tested before it is published to ECR Public. Must stay publicly pullable: customer clusters cannot pull from Ravion's private ECR."
  default     = "oci://public.ecr.aws/a8z1i1r2/operator"
  nullable    = false

  validation {
    condition     = length(var.ravion_operator_chart_source) > 0
    error_message = "The ravion_operator_chart_source must not be empty."
  }
}

variable "ravion_operator_chart_version" {
  type        = string
  description = "Operator Helm chart version. For executor Jobs, use the chart_version output from the same Operator publishing run as ravion_operator_execution_image. Inline mode preserves the running image unless an image tag is pinned; Job mode pins coordinators and executors to ravion_operator_execution_image. Null tracks latest and is not allowed in Job mode."
  default     = "0.4.1"

  validation {
    condition     = var.ravion_operator_chart_version == null || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.ravion_operator_chart_version))
    error_message = "The ravion_operator_chart_version must be a semantic version like '0.2.0' (no leading 'v')."
  }
}

variable "ravion_operator_namespace" {
  type        = string
  description = "Kubernetes namespace the agent and its credential Secret are installed into. Created if it does not exist."
  default     = "ravion-operator"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.ravion_operator_namespace))
    error_message = "The ravion_operator_namespace must be a valid Kubernetes namespace: 1-63 lowercase letters, digits, or hyphens, starting and ending with a letter or digit."
  }
}

variable "ravion_operator_namespaces_creation_enabled" {
  type        = bool
  description = "Create missing observation and deployment namespaces before installing Ravion Operator RBAC. Existing namespaces are reused without adoption. Created namespaces are retained when removed from the configuration or when the add-ons are destroyed. Disable only when namespaces are provisioned separately."
  default     = true
  nullable    = false
}

variable "ravion_operator_namespace_scope" {
  type        = list(string)
  description = "Namespaces the agent may observe. Empty (the default) is the whole cluster. Non-empty renders no observation ClusterRole at all — one namespaced Role and RoleBinding per entry instead — so the restriction is enforced by Kubernetes rather than by the agent. A scoped install can read no nodes and no namespaces, so the node count in fleet health is reported as unknown."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for namespace in var.ravion_operator_namespace_scope : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", namespace))])
    error_message = "Each ravion_operator_namespace_scope entry must be a valid Kubernetes namespace (1-63 lowercase letters, digits, or hyphens, starting and ending with a letter or digit)."
  }
}

variable "ravion_operator_deploy_enabled" {
  type        = bool
  description = "Let Operator deploy workloads from inside the cluster. By default writes are limited to named namespaces and exclude RBAC and cluster-scoped objects. Explicit ravion_operator_full_management_enabled grants cluster-wide resource management through executor Jobs."
  default     = false
  nullable    = false
}

variable "ravion_operator_deploy_namespaces" {
  type        = list(string)
  description = "Namespaces Operator may deploy into, falling back to ravion_operator_namespace_scope when empty. Required for namespace-scoped deployment. Full management requires both lists empty and grants cluster-wide writes explicitly."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for namespace in var.ravion_operator_deploy_namespaces : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", namespace))])
    error_message = "Each ravion_operator_deploy_namespaces entry must be a valid Kubernetes namespace (1-63 lowercase letters, digits, or hyphens, starting and ending with a letter or digit)."
  }
}

variable "ravion_operator_exec_enabled" {
  type        = bool
  description = "Grant a separate ClusterRole allowing 'create' on pods/exec, the only way Ravion Operator can run a command inside a container. Off by default, recorded on the agent's credential as well as granted in the cluster, and scoped with ravion_operator_namespace_scope when that is set."
  default     = false
  nullable    = false
}

variable "ravion_operator_self_update_enabled" {
  type        = bool
  description = "Let the control plane roll the agent forward by patching its own Deployment. The only write permission the chart creates by default: a namespaced Role scoped by resourceNames to Ravion Operator's own Deployment. Turning it off pins the agent to whatever this module last applied, and you take on keeping it current — Ravion supports two agent minor versions back."
  default     = true
  nullable    = false
}

variable "ravion_operator_image_tag" {
  type        = string
  description = "Agent image tag to PIN. Leave null (the default): a fresh install then starts at the chart's appVersion and every later apply keeps whatever version the release is running, because the control plane owns the agent version and the chart re-emits the running image on upgrade. Set it only to force a specific agent version onto a cluster: while it is set every apply re-asserts it, a control-plane rollout in between included, and removing it hands the version back to the control plane on the next apply. It is a pin, not a one-off - leave it null unless you mean to hold a cluster at a version."
  default     = null
}

variable "ravion_operator_execution_jobs_enabled" {
  type        = bool
  description = "Run deployments in durable isolated executor Jobs. Requires deployments enabled and a digest-pinned execution image; automatically disables self-update in both enrollment and Helm. Drain inline deployments and remediation before switching modes."
  default     = false
  nullable    = false
}

variable "ravion_operator_execution_image" {
  type        = string
  description = "Full Operator image reference pinned by sha256 digest (image_ref from the publishing pipeline). Used by both coordinators and executor Jobs."
  default     = ""
  nullable    = false

  validation {
    condition     = var.ravion_operator_execution_image == "" || can(regex("^[^@\\s]+@sha256:[a-f0-9]{64}$", var.ravion_operator_execution_image))
    error_message = "The ravion_operator_execution_image must be empty or a full image reference pinned by sha256 digest."
  }
}

variable "ravion_operator_execution_max_concurrent" {
  type        = number
  description = "Installation-wide retained executor capacity (1-64), not per coordinator. Changing established capacity requires draining executions and migrating the retained capacity Lease. Full management requires 1."
  default     = 1
  nullable    = false

  validation {
    condition     = var.ravion_operator_execution_max_concurrent >= 1 && var.ravion_operator_execution_max_concurrent <= 64 && floor(var.ravion_operator_execution_max_concurrent) == var.ravion_operator_execution_max_concurrent
    error_message = "The ravion_operator_execution_max_concurrent must be an integer from 1 to 64."
  }
}

variable "ravion_operator_coordinator_enabled" {
  type        = bool
  description = "Enable elected HA coordinators. Requires executor Jobs and a replica-aware Ravion gateway."
  default     = false
  nullable    = false
}

variable "ravion_operator_coordinator_replicas" {
  type        = number
  description = "HA coordinator replica count (2-9). Each coordinator requests 500m CPU and 1Gi memory by default."
  default     = 3
  nullable    = false

  validation {
    condition     = var.ravion_operator_coordinator_replicas >= 2 && var.ravion_operator_coordinator_replicas <= 9 && floor(var.ravion_operator_coordinator_replicas) == var.ravion_operator_coordinator_replicas
    error_message = "The ravion_operator_coordinator_replicas must be an integer from 2 to 9."
  }
}

variable "ravion_operator_coordinator_distinct_nodes_enabled" {
  type        = bool
  description = "Require a distinct node per HA coordinator. Disable only for small test clusters or when supplying custom affinity through Helm values."
  default     = true
  nullable    = false
}

variable "ravion_operator_full_management_enabled" {
  type        = bool
  description = "Grant explicit wildcard Kubernetes RBAC for all resources, including CRDs, RBAC, namespaces and custom resources. Requires executor Jobs, empty observation/deployment namespace lists and one retained mutation lane. Drain existing ownership before changing this scope."
  default     = false
  nullable    = false
}

variable "ravion_operator_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the Ravion Operator chart values (later entries win). The route to values this module does not surface directly, e.g. portForward.enabled, helmInventory.enabled, redaction.extraPatterns, image.repository, resources, or tolerations."
  default     = []
  nullable    = false
}

variable "ravion_operator_project_id" {
  type        = string
  description = "Ravion project this cluster belongs to, recorded on the agent when its credential is minted. Optional; the cluster identity alone is enough."
  default     = null
}

variable "ravion_operator_environment_id" {
  type        = string
  description = "Ravion environment this cluster belongs to, recorded on the agent when its credential is minted. Optional."
  default     = null
}

variable "ravion_operator_aws_account_record_id" {
  type        = string
  description = "Ravion AWS account record the cluster lives in, recorded on the agent when its credential is minted. This is the Ravion record id (awsact_...), not the 12-digit AWS account number. Optional."
  default     = null
}

################################################################################
# Workload metrics (Amazon Managed Prometheus)
################################################################################

variable "amp_workspace_id" {
  type        = string
  description = "Existing Amazon Managed Prometheus workspace to write into (ws-...). When null, the module creates one for this cluster. Bring your own to share a workspace between clusters, or to write into a workspace in another region."
  default     = null

  validation {
    condition     = var.amp_workspace_id == null || can(regex("^ws-[0-9a-fA-F-]+$", var.amp_workspace_id))
    error_message = "The amp_workspace_id must be an AMP workspace id like 'ws-12345678-abcd-1234-abcd-123456789012'."
  }
}

variable "amp_region" {
  type        = string
  description = "Region the AMP workspace lives in. When null, the cluster's region is used. Set this for clusters in regions where AMP is unavailable: remote write works cross-region, at the cost of inter-region data transfer."
  default     = null
}

variable "amp_alias" {
  type        = string
  description = "Alias for the created AMP workspace. When null, 'ravion-<cluster_name>' is used. Ignored when amp_workspace_id is set."
  default     = null

  validation {
    condition     = var.amp_alias == null || can(regex("^[0-9A-Za-z][-._0-9A-Za-z]{0,99}$", var.amp_alias))
    error_message = "The amp_alias must be 1-100 characters of alphanumerics, hyphens, dots, or underscores."
  }
}

variable "metrics_namespace" {
  type        = string
  description = "Kubernetes namespace the metrics components (kube-state-metrics, OpenTelemetry collector) are installed into. When null, Ravion Operator's namespace is used, so Ravion's in-cluster components share one namespace. Created if it does not exist."
  default     = null
}

variable "scrape_interval_seconds" {
  type        = number
  description = "How often the collector scrapes each target. Sample count - and therefore AMP cost - scales inversely with this, so lengthening it is the first cost lever."
  default     = 60
  nullable    = false

  validation {
    condition     = var.scrape_interval_seconds >= 15 && var.scrape_interval_seconds <= 300
    error_message = "The scrape_interval_seconds must be between 15 and 300."
  }
}

variable "metrics_additional_allowlist" {
  type        = list(string)
  description = "Extra metric-name regexes appended to the curated allow-list on every scrape job. Anything not matched by the base list or by these is dropped before it enters collector memory, so this is the only way to widen what reaches AMP. Entries are alternation branches in a fully anchored regex - 'my_app_.*', not '.*my_app.*'."
  default     = []
  nullable    = false
}

variable "otel_collector_chart_version" {
  type        = string
  description = "Version of the community opentelemetry-collector Helm chart used to run the collector."
  default     = "0.169.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.otel_collector_chart_version))
    error_message = "The otel_collector_chart_version must be a semantic version like '0.169.0' (no leading 'v')."
  }
}

variable "otel_collector_image_repository" {
  type        = string
  description = "Metrics collector image. When null the module chooses: the AWS Distro for OpenTelemetry (public.ecr.aws/aws-observability/aws-otel-collector) for an AMP-only or CloudWatch-only selection, and the upstream contrib distribution when a vendor provider is selected, because the AWS Distro does not ship the datadog exporter or the basicauth extension. Point this at a private mirror if the cluster cannot reach the registry."
  default     = null
}

variable "otel_collector_image_tag" {
  type        = string
  description = "Tag of the metrics collector image. When null it follows the image the module chose: v0.49.0 for the AWS Distro, otel_contrib_image_tag for contrib."
  default     = null
}

variable "otel_collector_command_name" {
  type        = string
  description = "Binary the metrics collector container runs, as the chart's command.name (it renders '/<name>'). When null it follows the chosen image: 'awscollector' for the AWS Distro, 'otelcol-contrib' for contrib."
  default     = null
}

variable "otel_collector_service_account" {
  type        = string
  description = "Service account the collector runs as. The Pod Identity association binds the AMP remote-write role to this name, so the chart and the association are driven from this single value."
  default     = "ravion-otel-collector"
  nullable    = false
}

variable "otel_collector_resources" {
  type = object({
    cpu_request    = optional(string, "100m")
    memory_request = optional(string, "256Mi")
    cpu_limit      = optional(string)
    memory_limit   = optional(string, "512Mi")
  })
  description = "Resource requests and limits for the collector pod. A memory limit is set by default because the collector's memory_limiter processor sizes itself as a percentage of the container limit - with no limit it would measure against the whole node. Null limits are omitted."
  default     = {}
  nullable    = false
}

variable "otel_collector_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the opentelemetry-collector chart values, after the values this module derives (later entries win). The route to tolerations, node selectors, extra scrape jobs, or a second exporter."
  default     = []
  nullable    = false
}

variable "kube_state_metrics_enabled" {
  type        = bool
  description = "Install kube-state-metrics alongside the collector. It is the source of every kube_* series in the allow-list (replica counts, restart reasons, pod phase, node conditions), so turning it off leaves only cAdvisor and kubelet metrics. Only takes effect when metrics_enabled is true."
  default     = true
  nullable    = false
}

variable "kube_state_metrics_chart_version" {
  type        = string
  description = "Version of the prometheus-community/kube-state-metrics Helm chart to install."
  default     = "8.3.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.kube_state_metrics_chart_version))
    error_message = "The kube_state_metrics_chart_version must be a semantic version like '8.3.0' (no leading 'v')."
  }
}

variable "kube_state_metrics_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the kube-state-metrics chart values (later entries win), e.g. a narrowed 'collectors' list or a private image registry."
  default     = []
  nullable    = false
}

################################################################################
# Grafana read access
################################################################################

variable "grafana_role_creation_enabled" {
  type        = bool
  description = "Create an IAM role that Amazon Managed Grafana can assume to read this cluster's telemetry: query access to the AMP workspace and read access to the Container Insights log groups. No Grafana workspace is created - provisioning one requires IAM Identity Center wiring that belongs at the organization level, not in a cluster module."
  default     = false
  nullable    = false
}

variable "grafana_source_account_id" {
  type        = string
  description = "AWS account whose Grafana workspaces may assume the read role, enforced with an aws:SourceAccount condition. When null, this account is used. Set it to the account that hosts the Grafana workspace when that differs from the cluster's account."
  default     = null

  validation {
    condition     = var.grafana_source_account_id == null || can(regex("^[0-9]{12}$", var.grafana_source_account_id))
    error_message = "The grafana_source_account_id must be a 12-digit AWS account id."
  }
}

################################################################################
# Workload logs (Loki on S3)
################################################################################

variable "loki_s3_bucket_name" {
  type        = string
  description = "Existing S3 bucket to store log chunks and the index in. When null, the module creates 'ravion-loki-<cluster>-<account>'. Bring your own to control naming, encryption, or lifecycle policy yourself - the module then manages neither the bucket nor its retention."
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "How long logs are queryable. Enforced by Loki's compactor, which deletes chunks whose retention has expired; the created bucket additionally carries a lifecycle expiration a week later as a backstop for anything the compactor orphans."
  default     = 30
  nullable    = false

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3650
    error_message = "The log_retention_days must be between 1 and 3650."
  }
}

variable "logs_namespace" {
  type        = string
  description = "Kubernetes namespace Loki and Alloy are installed into. When null, Ravion Operator's namespace is used, so Ravion's in-cluster components share one namespace. Created if it does not exist."
  default     = null
}

variable "loki_chart_version" {
  type        = string
  description = "Version of the grafana/loki Helm chart to install."
  default     = "7.3.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.loki_chart_version))
    error_message = "The loki_chart_version must be a semantic version like '7.3.0' (no leading 'v')."
  }
}

variable "loki_service_account" {
  type        = string
  description = "Service account Loki runs as. The Pod Identity association binds the S3 role to this name, so the chart and the association are driven from this single value."
  default     = "ravion-loki"
  nullable    = false
}

variable "loki_resources" {
  type = object({
    cpu_request    = optional(string, "200m")
    memory_request = optional(string, "512Mi")
    cpu_limit      = optional(string)
    memory_limit   = optional(string, "1Gi")
  })
  description = "Resource requests and limits for the Loki pod. Sized for a small cluster in single-binary mode; raise the memory limit before raising anything else, because query fan-out over many streams is what pushes Loki over. Null limits are omitted."
  default     = {}
  nullable    = false
}

variable "loki_persistence_enabled" {
  type        = bool
  description = "Give Loki a PersistentVolumeClaim for its write-ahead log and index cache. Off by default because it needs a working StorageClass - on a Ravion cluster that means ebs_csi_driver_enabled - and an unschedulable PVC is a worse first run than an ephemeral one. With it off, chunks still land in S3; what is lost on a restart is the few minutes of logs not yet flushed."
  default     = false
  nullable    = false
}

variable "loki_persistence_size" {
  type        = string
  description = "Size of Loki's local working volume, which holds the write-ahead log, the compactor's working directory, and the index cache - not the logs themselves, which are in S3. Becomes the PersistentVolumeClaim size when loki_persistence_enabled is true, and the emptyDir size limit when it is false."
  default     = "10Gi"
  nullable    = false
}

variable "loki_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the grafana/loki chart values, after the values this module derives (later entries win). The route to simple-scalable mode, caches, tolerations, or a private image registry."
  default     = []
  nullable    = false
}

variable "alloy_chart_version" {
  type        = string
  description = "Version of the grafana/alloy Helm chart to install."
  default     = "1.11.1"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.alloy_chart_version))
    error_message = "The alloy_chart_version must be a semantic version like '1.11.1' (no leading 'v')."
  }
}

variable "alloy_resources" {
  type = object({
    cpu_request    = optional(string, "100m")
    memory_request = optional(string, "128Mi")
    cpu_limit      = optional(string)
    memory_limit   = optional(string, "512Mi")
  })
  description = "Resource requests and limits for each Alloy pod. It runs on every node, so this is multiplied by the node count - the defaults are deliberately small. Null limits are omitted."
  default     = {}
  nullable    = false
}

variable "alloy_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the grafana/alloy chart values, after the values this module derives (later entries win). The route to tolerations, node selectors, or extra Alloy components."
  default     = []
  nullable    = false
}

################################################################################
# In-cluster Grafana
################################################################################

variable "grafana_enabled" {
  type        = bool
  description = "Install Grafana in the cluster, preprovisioned with both Ravion datasources: Amazon Managed Prometheus over SigV4 and the in-cluster Loki. This is the only way to see the logs in Grafana - Amazon Managed Grafana runs outside the cluster and cannot reach Loki, which is deliberately not exposed. No ingress is created; reach it with a port-forward or add one through grafana_helm_values."
  default     = false
  nullable    = false
}

variable "grafana_chart_version" {
  type        = string
  description = "Version of the grafana Helm chart to install, from the grafana-community repository - the maintained home of this chart since Grafana Labs deprecated their copy in January 2026."
  default     = "12.10.4"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.grafana_chart_version))
    error_message = "The grafana_chart_version must be a semantic version like '12.10.4' (no leading 'v')."
  }
}

variable "grafana_namespace" {
  type        = string
  description = "Kubernetes namespace Grafana is installed into. When null, Ravion Operator's namespace is used. Created if it does not exist."
  default     = null
}

variable "grafana_service_account" {
  type        = string
  description = "Service account Grafana runs as. The Pod Identity association binds the Amazon Managed Prometheus read role to this name, so Grafana's SigV4 datasource signs with credentials it never stores."
  default     = "ravion-grafana"
  nullable    = false
}

variable "grafana_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the grafana/grafana chart values, after the values this module derives (later entries win). The route to an ingress, persistence, an admin password from an existing secret, dashboards, or resources."
  default     = []
  nullable    = false
}

################################################################################
# Observability providers
#
# One multi-select per signal. Loki (in-cluster) and Amazon Managed Prometheus
# are the defaults: a fresh instance gets Ravion's full Logs and Metrics
# experience with no configuration, and nothing CloudWatch is ever installed as
# a side effect. Every other destination — including CloudWatch — is a member of
# these lists and nothing more.
#
# Rendering providers form a FALLBACK CHAIN in the dashboard, never a merge:
# logs loki -> cloudwatch, metrics amp -> prometheus -> cloudwatch. Ship-only
# providers stack freely; the collectors fan out to all of them at once.
################################################################################

variable "logs_providers" {
  type        = list(string)
  description = "Where container logs go. Any combination of: loki (in-cluster store on S3, renders in Ravion), cloudwatch (CloudWatch Logs, renders in Ravion), grafana_cloud, datadog, new_relic, opensearch, splunk, otlp. An empty list turns logs off entirely — no collector, no store."
  default     = ["loki"]
  nullable    = false

  validation {
    condition = alltrue([
      for provider in var.logs_providers :
      contains(["loki", "cloudwatch", "grafana_cloud", "datadog", "new_relic", "opensearch", "splunk", "otlp"], provider)
    ])
    error_message = "Each logs_providers entry must be one of: loki, cloudwatch, grafana_cloud, datadog, new_relic, opensearch, splunk, otlp."
  }
}

variable "metrics_providers" {
  type        = list(string)
  description = "Where workload metrics go. Any combination of: amp (Amazon Managed Prometheus, renders in Ravion), prometheus (in-cluster, renders through Ravion Operator), cloudwatch (Container Insights, renders in Ravion), grafana_cloud, datadog, new_relic, otlp. An empty list turns metrics off entirely."
  default     = ["amp"]
  nullable    = false

  validation {
    condition = alltrue([
      for provider in var.metrics_providers :
      contains(["amp", "prometheus", "cloudwatch", "grafana_cloud", "datadog", "new_relic", "otlp"], provider)
    ])
    error_message = "Each metrics_providers entry must be one of: amp, prometheus, cloudwatch, grafana_cloud, datadog, new_relic, otlp."
  }
}

variable "observability_namespace" {
  type        = string
  description = "Kubernetes namespace the collectors, kube-state-metrics, the log store and the materialized vendor credentials are installed into. When null, Ravion Operator's namespace is used, so Ravion's in-cluster components share one namespace — and, importantly, Loki keeps the Service URL the control plane already defaults to. Created if it does not exist."
  default     = null
}

variable "logs_excluded_namespaces" {
  type        = list(string)
  description = "Namespaces no log collector reads from. Applies to every logs provider: Alloy drops them at discovery, the OpenTelemetry collector never opens their files. Ravion's own namespace is excluded by default so the collectors do not tail themselves into a loop."
  default     = ["kube-system", "kube-node-lease", "amazon-cloudwatch", "ravion-operator", "ravion-beacon"]
  nullable    = false
}

################################################################################
# Per-provider settings
#
# One object per provider. Only the objects whose provider is selected are read,
# so passing them all is free. Every field is optional: where a field has an
# older flat variable (log_retention_days, loki_s3_bucket_name, amp_workspace_id,
# amp_region, cloudwatch_observability_addon_version), the object wins and the
# flat variable is the fallback.
#
# Vendor credentials are ALWAYS Secrets Manager ARNs, never values: the External
# Secrets Operator materializes them into Kubernetes Secrets in the collector's
# namespace, so nothing sensitive passes through Ravion, Helm values, or release
# history. Selecting a vendor provider therefore requires eso_enabled.
################################################################################

variable "logs_loki" {
  type = object({
    retention_days      = optional(number)
    s3_bucket_name      = optional(string)
    persistence_enabled = optional(bool)
    persistence_size    = optional(string)
  })
  description = "In-cluster Loki settings: how long logs stay queryable, an existing bucket to store chunks in, and the local working volume. Falls back to log_retention_days / loki_s3_bucket_name / loki_persistence_* when a field is null."
  default     = {}
  nullable    = false
}

variable "logs_cloudwatch" {
  type = object({
    retention_days = optional(number)
    log_group_name = optional(string)
  })
  description = "CloudWatch Logs settings. The default log group is /ravion/eks/<cluster>, one stream per pod named <namespace>/<pod>/<container>."
  default     = {}
  nullable    = false
}

variable "logs_grafana_cloud" {
  type = object({
    url              = optional(string)
    user             = optional(string)
    token_secret_arn = optional(string)
    stack_url        = optional(string)
  })
  description = "Grafana Cloud Logs: the Loki push URL, the numeric user/tenant id, a Secrets Manager ARN holding the access token, and (optionally) the stack URL used to build the 'Open in Grafana' link. Alloy writes here with basic auth, alongside any other loki-family destination."
  default     = {}
  nullable    = false
}

variable "logs_datadog" {
  type = object({
    site               = optional(string)
    api_key_secret_arn = optional(string)
  })
  description = "Datadog logs: the site (datadoghq.com, datadoghq.eu, ...) and a Secrets Manager ARN holding the API key. Shared with metrics_datadog when both signals pick Datadog."
  default     = {}
  nullable    = false
}

variable "logs_new_relic" {
  type = object({
    region                 = optional(string)
    license_key_secret_arn = optional(string)
  })
  description = "New Relic logs: region (us or eu, deciding the OTLP endpoint) and a Secrets Manager ARN holding the license key."
  default     = {}
  nullable    = false
}



variable "logs_opensearch" {
  type = object({
    endpoint     = optional(string)
    index_prefix = optional(string)
  })
  description = "Amazon OpenSearch Service: the domain endpoint (https://...) and the index prefix. Requests are signed with SigV4 from the collector's Pod Identity role, so the domain's access policy or its fine-grained role mapping has to name logs_opensearch_role_arn - the module cannot do that from outside the domain."
  default     = {}
  nullable    = false
}

variable "logs_splunk" {
  type = object({
    hec_url              = optional(string)
    hec_token_secret_arn = optional(string)
    index                = optional(string)
  })
  description = "Splunk HTTP Event Collector: the HEC URL, a Secrets Manager ARN holding the token, and the target index."
  default     = {}
  nullable    = false
}

variable "logs_otlp" {
  type = object({
    endpoint           = optional(string)
    headers_secret_arn = optional(string)
  })
  description = "Any OTLP/HTTP log receiver: the endpoint, and optionally a Secrets Manager ARN holding the value of an Authorization header the collector sends with every request."
  default     = {}
  nullable    = false
}

variable "metrics_amp" {
  type = object({
    workspace_id = optional(string)
    region       = optional(string)
    alias        = optional(string)
  })
  description = "Amazon Managed Prometheus: an existing workspace to write into, the region it lives in, and the alias for a created one. Falls back to amp_workspace_id / amp_region / amp_alias."
  default     = {}
  nullable    = false
}

variable "metrics_cloudwatch" {
  type = object({
    enhanced_observability_enabled = optional(bool)
    application_signals_enabled    = optional(bool)
    application_signals_namespaces = optional(list(string))
    addon_version                  = optional(string)
    addon_configuration_values     = optional(string)
  })
  description = "CloudWatch Container Insights. Application Signals auto-instrumentation is OFF unless application_signals_enabled is true: with it on, the add-on's Auto-Monitor webhook injects the AWS OpenTelemetry agent into workloads and restarts their pods, which is exactly the behaviour that used to be silently on. Falls back to cloudwatch_observability_addon_version / cloudwatch_observability_addon_configuration_values."
  default     = {}
  nullable    = false
}


variable "metrics_prometheus" {
  type = object({
    retention_days = optional(number)
    storage_size   = optional(string)
    endpoint       = optional(string)
  })
  description = "Prometheus running in the cluster, with the remote-write receiver on and a PersistentVolume behind it. Set endpoint to point at a Prometheus you already run, and the module installs nothing and only remote-writes to it. Installing needs a working StorageClass, which on a Ravion cluster means ebs_csi_driver_enabled."
  default     = {}
  nullable    = false
}

variable "metrics_grafana_cloud" {
  type = object({
    url              = optional(string)
    user             = optional(string)
    token_secret_arn = optional(string)
    stack_url        = optional(string)
  })
  description = "Grafana Cloud Metrics: the Prometheus remote-write URL, the numeric instance/user id, a Secrets Manager ARN holding the token, and (optionally) the stack URL for the 'Open in Grafana' link."
  default     = {}
  nullable    = false
}

variable "metrics_datadog" {
  type = object({
    site               = optional(string)
    api_key_secret_arn = optional(string)
  })
  description = "Datadog metrics: the site and a Secrets Manager ARN holding the API key. Shared with logs_datadog when both signals pick Datadog."
  default     = {}
  nullable    = false
}

variable "metrics_new_relic" {
  type = object({
    region                 = optional(string)
    license_key_secret_arn = optional(string)
  })
  description = "New Relic metrics: region (us or eu) and a Secrets Manager ARN holding the license key."
  default     = {}
  nullable    = false
}

variable "metrics_otlp" {
  type = object({
    endpoint           = optional(string)
    headers_secret_arn = optional(string)
  })
  description = "Any OTLP/HTTP metrics receiver: the endpoint, and optionally a Secrets Manager ARN holding the value of an Authorization header."
  default     = {}
  nullable    = false
}

################################################################################
# Log collector (OpenTelemetry)
#
# The second log collector, next to Alloy. Alloy carries the loki-family
# destinations because the dashboard's label contract is written against it;
# this one carries every other log destination, with one exporter per selected
# provider on a single pipeline.
################################################################################

variable "otel_logs_collector_service_account" {
  type        = string
  description = "Service account the log collector runs as. The Pod Identity association that lets it write to CloudWatch Logs or sign OpenSearch requests binds to this name."
  default     = "ravion-otel-logs-collector"
  nullable    = false
}

variable "otel_logs_collector_resources" {
  type = object({
    cpu_request    = optional(string, "100m")
    memory_request = optional(string, "128Mi")
    cpu_limit      = optional(string)
    memory_limit   = optional(string, "512Mi")
  })
  description = "Resource requests and limits for each log collector pod. It runs on every node, so this is multiplied by the node count. A memory limit is set by default because the collector's memory_limiter processor sizes itself as a percentage of the container limit."
  default     = {}
  nullable    = false
}

variable "otel_logs_collector_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the opentelemetry-collector chart values for the log collector (later entries win)."
  default     = []
  nullable    = false
}

variable "otel_contrib_image_repository" {
  type        = string
  description = "Image for collectors that need vendor exporters (datadog, splunk_hec, opensearch, awscloudwatchlogs). The AWS Distro does not ship them, so the log collector — and the metrics collector, when a vendor provider is selected — runs the upstream contrib distribution instead."
  default     = "docker.io/otel/opentelemetry-collector-contrib"
  nullable    = false
}

variable "otel_contrib_image_tag" {
  type        = string
  description = "Tag of the contrib collector image."
  default     = "0.137.0"
  nullable    = false
}

variable "otel_contrib_command_name" {
  type        = string
  description = "Binary the contrib collector container runs, as the chart's command.name (it renders '/<name>')."
  default     = "otelcol-contrib"
  nullable    = false
}



################################################################################
# In-cluster Prometheus
################################################################################

variable "prometheus_chart_version" {
  type        = string
  description = "Version of the prometheus-community/prometheus Helm chart installed for the in-cluster prometheus provider."
  default     = "27.44.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.prometheus_chart_version))
    error_message = "The prometheus_chart_version must be a semantic version like '27.44.0' (no leading 'v')."
  }
}

variable "prometheus_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the prometheus chart values, after the values this module derives (later entries win). The route to alerting rules, extra scrape jobs, or a private image registry."
  default     = []
  nullable    = false
}
