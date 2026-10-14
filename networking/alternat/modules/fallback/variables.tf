variable "nat_gateways" {
  type = list(object({
    id                = string
    subnet_id         = string
    connectivity_type = string
  }))
  description = "Available NAT gateways in the VPC, public and private."
}

variable "nat_instances" {
  type = list(object({
    availability_zone = string
    public_subnet_id  = string
  }))
  description = "Each alterNAT instance's availability zone and public subnet."
}

variable "fallback_nat_gateway_id" {
  type        = string
  description = "NAT gateway chosen explicitly as every alterNAT instance's fallback, or null."
  default     = null
}
