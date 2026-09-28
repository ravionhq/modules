terraform {
  required_version = ">= 1.10.0"
}

variable "name" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = null
}

variable "vpc_zone_identifier" {
  type = list(string)
}

variable "launch_template_creation_enabled" {
  type = bool
}

variable "launch_template_id" {
  type = string
}

module "group" {
  source = "../.."

  name                             = var.name
  name_prefix                      = var.name_prefix
  vpc_zone_identifier              = var.vpc_zone_identifier
  launch_template_creation_enabled = var.launch_template_creation_enabled
  launch_template_id               = var.launch_template_id
}

output "group_id" {
  value = module.group.autoscaling_group_id
}

output "group_name" {
  value = module.group.autoscaling_group_name
}
