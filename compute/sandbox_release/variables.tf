################################################################################
# Inputs
################################################################################

variable "region" {
  description = "Region the release is published in. Hosts read the release of the region they run in, so a release is published once per region it is used in."
  type        = string
}

variable "parameter_name" {
  description = "SSM parameter the release is published at. Every pool in this region reads it when it plans."
  type        = string
  default     = "/ravion/sandbox-host/release"

  validation {
    condition     = can(regex("^/[A-Za-z0-9._/-]{1,1000}$", var.parameter_name))
    error_message = "The parameter name must start with / and hold only letters, numbers, dots, underscores, hyphens and slashes."
  }
}

variable "runner_version" {
  description = "Runner release the hosts boot, as the image is tagged: v1.2.3."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.runner_version))
    error_message = "The runner version must look like v1.2.3."
  }
}

variable "guest_image_key" {
  description = "Guest image the hosts boot, as the image is tagged and as the release bucket names it: guest/<16 hex characters>."
  type        = string

  validation {
    condition     = can(regex("^guest/[0-9a-f]{16}$", var.guest_image_key))
    error_message = "The guest image key must look like guest/0123456789abcdef."
  }
}

variable "verify_image" {
  description = "Refuse to publish a release no image in this region carries. Leave on: a published release whose image is missing is a pool that cannot launch, discovered at the next launch rather than here."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the parameter."
  type        = map(string)
  default     = {}
}
