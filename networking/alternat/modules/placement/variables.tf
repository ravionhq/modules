variable "public_subnets" {
  type = list(object({
    id                = string
    availability_zone = string
  }))
  description = "Public subnets the NAT instances may run in, in order of preference."
}

variable "private_subnets" {
  type = list(object({
    id                = string
    availability_zone = string
    route_table_id    = string
  }))
  description = "Private subnets whose egress the NAT instances serve, with the route table each uses."
}

variable "high_availability_enabled" {
  type        = bool
  description = "Run one NAT instance per availability zone that has its own private route table."
}
