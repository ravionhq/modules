################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 36
    error_message = "The name must be between 1 and 36 characters to ensure S3 bucket names for VPC flow logs stay within the 63 character limit."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# VPC
################################################################################

variable "vpc_cidr" {
  type        = string
  description = "The IPv4 CIDR block for the VPC."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "dns_support_enabled" {
  type        = bool
  description = "Enable DNS support in the VPC."
  default     = true
}

variable "dns_hostnames_enabled" {
  type        = bool
  description = "Enable DNS hostnames in the VPC."
  default     = true
}

################################################################################
# Subnets
################################################################################

variable "subnet_count" {
  type        = number
  description = "The number of public and private subnet pairs to create. Each pair is placed in a different availability zone. If null, the module creates up to 3 subnet pairs, capped by the number of selected or available availability zones."
  default     = null

  validation {
    condition     = var.subnet_count == null || (var.subnet_count >= 1 && var.subnet_count <= 6)
    error_message = "The subnet_count must be null or between 1 and 6."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "A list of availability zones to use for subnets. If empty, AZs will be automatically selected."
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= 1
    error_message = "If specified, availability_zones must contain at least 1 AZ."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "A list of CIDR blocks for public subnets. If null, CIDRs will be automatically calculated from the VPC CIDR."
  default     = null

  validation {
    condition     = var.public_subnet_cidrs == null || alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All public_subnet_cidrs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = var.public_subnet_cidrs == null || var.subnet_count == null || length(var.public_subnet_cidrs) == var.subnet_count
    error_message = "The number of public_subnet_cidrs must equal subnet_count when subnet_count is set."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "A list of CIDR blocks for private subnets. If null, CIDRs will be automatically calculated from the VPC CIDR."
  default     = null

  validation {
    condition     = var.private_subnet_cidrs == null || alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All private_subnet_cidrs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = var.private_subnet_cidrs == null || var.subnet_count == null || length(var.private_subnet_cidrs) == var.subnet_count
    error_message = "The number of private_subnet_cidrs must equal subnet_count when subnet_count is set."
  }
}

################################################################################
# NAT Gateway
################################################################################

variable "nat_gateway_enabled" {
  type        = bool
  description = "Enable NAT Gateway(s) to allow private subnets to access the internet."
  default     = false
}

variable "nat_gateway_high_availability_enabled" {
  type        = bool
  description = "Deploy one NAT Gateway per AZ for high availability. Set to false (default) to use a single NAT Gateway for all private subnets (cost-effective)."
  default     = false
}

variable "single_nat_gateway" {
  type        = bool
  description = <<-EOT
    DEPRECATED: use `nat_gateway_high_availability_enabled` instead. This variable will
    be removed in a future major version. The semantics are inverted:
      - single_nat_gateway = true  → nat_gateway_high_availability_enabled = false
      - single_nat_gateway = false → nat_gateway_high_availability_enabled = true
    When set (non-null), this variable takes precedence over
    nat_gateway_high_availability_enabled.
  EOT
  default     = null
}

variable "nat_gateway_eip_allocation_ids" {
  type        = list(string)
  description = <<-EOT
    A list of pre-allocated Elastic IP allocation IDs (for example from the
    networking/eips module) to associate with the NAT Gateway(s). When null or
    empty (default), the module allocates new EIPs internally.

    The list length must match the number of NAT Gateways the module will create:
      - 1 when nat_gateway_high_availability_enabled = false
      - the resolved subnet count when nat_gateway_high_availability_enabled = true
        (run a plan first to discover the resolved count when subnet_count is null)

    Supplied EIPs must already exist with domain = "vpc". This is useful for
    keeping NAT public IPs stable across VPC replacements (e.g. for partner
    allowlists or firewall rules).
  EOT
  default     = null

  validation {
    condition = (
      var.nat_gateway_eip_allocation_ids == null ||
      alltrue([
        for id in coalesce(var.nat_gateway_eip_allocation_ids, []) :
        can(regex("^eipalloc-[a-f0-9]+$", id))
      ])
    )
    error_message = "Each nat_gateway_eip_allocation_ids entry must be a valid EIP allocation ID (e.g. eipalloc-0123456789abcdef0)."
  }

  validation {
    condition = (
      var.nat_gateway_eip_allocation_ids == null ||
      !var.nat_gateway_enabled ||
      length(var.nat_gateway_eip_allocation_ids) == 0 ||
      (!(var.single_nat_gateway != null ? !var.single_nat_gateway : var.nat_gateway_high_availability_enabled) && length(var.nat_gateway_eip_allocation_ids) == 1) ||
      ((var.single_nat_gateway != null ? !var.single_nat_gateway : var.nat_gateway_high_availability_enabled) && var.subnet_count != null && length(var.nat_gateway_eip_allocation_ids) == var.subnet_count) ||
      ((var.single_nat_gateway != null ? !var.single_nat_gateway : var.nat_gateway_high_availability_enabled) && var.subnet_count == null)
    )
    error_message = "The number of nat_gateway_eip_allocation_ids must equal 1 for single-NAT mode, or subnet_count for HA mode when subnet_count is set. Automatic subnet counts are checked during planning."
  }
}

################################################################################
# VPC Endpoints
################################################################################

variable "vpc_endpoint_s3_gateway_enabled" {
  type        = bool
  description = "Create a free S3 gateway VPC endpoint and attach it to all route tables. S3 traffic stays inside AWS instead of routing through the NAT gateway, avoiding NAT data processing charges (including ECR image layer pulls)."
  default     = false
}

variable "vpc_endpoint_dynamodb_gateway_enabled" {
  type        = bool
  description = "Create a free DynamoDB gateway VPC endpoint and attach it to all route tables. DynamoDB traffic stays inside AWS instead of routing through the NAT gateway."
  default     = false
}

variable "vpc_endpoint_interface_services" {
  type        = list(string)
  description = <<-EOT
    A list of AWS service short names to create interface VPC endpoints
    (PrivateLink) for, e.g. ["ecr.api", "ecr.dkr", "logs", "secretsmanager"].
    Each service name is appended to "com.amazonaws.<region>." to form the full
    endpoint service name.

    Endpoints are placed in every private subnet with private DNS enabled and
    share a module-managed security group allowing HTTPS (443) from the VPC
    CIDR. Requires dns_support_enabled and dns_hostnames_enabled.

    Note: pulling ECR images privately requires "ecr.api", "ecr.dkr", and the
    S3 gateway endpoint together. Interface endpoints are billed per hour per
    AZ plus per GB processed.
  EOT
  default     = []

  validation {
    condition = alltrue([
      for service in coalesce(var.vpc_endpoint_interface_services, []) :
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", service))
    ])
    error_message = "Each vpc_endpoint_interface_services entry must be a lowercase AWS service short name (e.g. ecr.api, logs, secretsmanager)."
  }
}

################################################################################
# IPv6
################################################################################

variable "ipv6_enabled" {
  type        = bool
  description = "Enable IPv6 support for the VPC. An Amazon-provided IPv6 CIDR block will be assigned."
  default     = false
}

################################################################################
# VPC Flow Logs
################################################################################

variable "flow_logs_enabled" {
  type        = bool
  description = "Enable VPC Flow Logs for network traffic monitoring."
  default     = false
}

variable "flow_logs_destination" {
  type        = string
  description = "The destination for VPC Flow Logs. Valid values: 'cloudwatch' or 's3'."
  default     = "cloudwatch"

  validation {
    condition     = contains(["cloudwatch", "s3"], var.flow_logs_destination)
    error_message = "The flow_logs_destination must be either 'cloudwatch' or 's3'."
  }
}

variable "flow_logs_s3_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for VPC Flow Logs. If null and destination is 's3', a new bucket will be created."
  default     = null

  validation {
    condition     = var.flow_logs_s3_bucket_arn == null || can(regex("^arn:aws:s3:::", var.flow_logs_s3_bucket_arn))
    error_message = "The flow_logs_s3_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "flow_logs_retention_days" {
  type        = number
  description = "The number of days to retain VPC Flow Logs in CloudWatch. Only applies when flow_logs_destination is 'cloudwatch'. Set to 0 for indefinite retention."
  default     = 30

  validation {
    condition = contains([
      0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365,
      400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.flow_logs_retention_days)
    error_message = "The flow_logs_retention_days must be a valid CloudWatch Logs retention value."
  }
}

variable "flow_logs_traffic_type" {
  type        = string
  description = "The type of traffic to capture in VPC Flow Logs. Valid values: 'ACCEPT', 'REJECT', or 'ALL'."
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "The flow_logs_traffic_type must be 'ACCEPT', 'REJECT', or 'ALL'."
  }
}

variable "flow_logs_kms_key_id" {
  type        = string
  description = "KMS key ID for S3 bucket encryption. If null, uses AES256 (SSE-S3)."
  default     = null

  validation {
    condition     = var.flow_logs_kms_key_id == null || can(regex("^(arn:aws:kms:|alias/)", var.flow_logs_kms_key_id))
    error_message = "The flow_logs_kms_key_id must be a valid KMS key ARN or alias."
  }
}

variable "flow_logs_versioning_enabled" {
  type        = bool
  description = "Enable versioning for the flow logs S3 bucket."
  default     = false
}

################################################################################
# VPC Peering
################################################################################

variable "vpc_peering_connections" {
  type = map(object({
    peer_vpc_id                        = string
    peer_cidr_blocks                   = list(string)
    peer_owner_id                      = optional(string)
    peer_region                        = optional(string)
    auto_accept                        = optional(bool, true)
    remote_vpc_dns_resolution_enabled  = optional(bool, false)
    public_route_table_routes_enabled  = optional(bool, true)
    private_route_table_routes_enabled = optional(bool, true)
    peer_route_table_ids               = optional(list(string), [])
    tags                               = optional(map(string), {})
  }))
  description = <<-EOT
    A map of VPC peering connections to create from this VPC to existing VPCs.

    The map key is a logical name used for the resource and tags. Each value configures
    one peering connection:
      - peer_vpc_id: The ID of the existing VPC to peer with.
      - peer_cidr_blocks: CIDR blocks of the peer VPC. Routes will be added in this
        VPC's route tables for each CIDR pointing at the peering connection.
      - peer_owner_id: AWS account ID that owns the peer VPC. Defaults to the current
        account. Required for cross-account peering.
      - peer_region: AWS region of the peer VPC. Defaults to the current region.
        Required for cross-region peering.
      - auto_accept: Whether to auto-accept the peering. Only valid for same-account,
        same-region peerings. For cross-account or cross-region, the peering must be
        accepted on the peer side.
      - remote_vpc_dns_resolution_enabled: Allow DNS resolution of private hostnames in
        the peer VPC from this VPC. Only valid for same-account, same-region peerings.
      - public_route_table_routes_enabled: Add routes for peer_cidr_blocks to this VPC's public
        route table.
      - private_route_table_routes_enabled: Add routes for peer_cidr_blocks to this VPC's
        private route table(s).
      - peer_route_table_ids: Optional list of route table IDs in the peer VPC to add
        return routes to (destination = this VPC's CIDR, target = the peering
        connection). Only supported for same-account, same-region peerings, since the
        AWS provider used by this module must have access to the peer's route tables.
        For cross-account or cross-region peerings, manage the return routes from the
        peer side instead.
      - tags: Additional tags to apply to the peering connection.

    NOTE: For cross-account or cross-region peerings, this module cannot manage the
    peer VPC's route tables. The owner of the peer VPC is responsible for adding
    return routes pointing at the peering connection.
  EOT
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.vpc_peering_connections : alltrue([
        for cidr in v.peer_cidr_blocks : can(cidrhost(cidr, 0))
      ])
    ])
    error_message = "All peer_cidr_blocks must be valid IPv4 CIDR blocks."
  }

  validation {
    condition = alltrue([
      for k, v in var.vpc_peering_connections : length(v.peer_cidr_blocks) > 0
    ])
    error_message = "Each peering connection must specify at least one peer CIDR block."
  }

  validation {
    condition = alltrue([
      for k, v in var.vpc_peering_connections : can(regex("^vpc-[a-f0-9]+$", v.peer_vpc_id))
    ])
    error_message = "Each peer_vpc_id must be a valid VPC ID (e.g., vpc-0123456789abcdef0)."
  }

  validation {
    condition = alltrue([
      for k, v in var.vpc_peering_connections :
      length(v.peer_route_table_ids) == 0 || (v.peer_owner_id == null && v.peer_region == null)
    ])
    error_message = "peer_route_table_ids can only be set for same-account, same-region peerings (peer_owner_id and peer_region must be null)."
  }

  validation {
    condition = alltrue([
      for k, v in var.vpc_peering_connections : alltrue([
        for rt_id in v.peer_route_table_ids : can(regex("^rtb-[a-f0-9]+$", rt_id))
      ])
    ])
    error_message = "Each peer_route_table_ids entry must be a valid route table ID (e.g., rtb-0123456789abcdef0)."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
