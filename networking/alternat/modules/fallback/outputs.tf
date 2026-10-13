output "public_nat_gateway_ids" {
  description = "Public NAT gateways available as a fallback."
  value       = local.public_nat_gateway_ids
}

output "fallback_nat_gateway_id" {
  description = "NAT gateway every alterNAT instance fails over to. Empty when each fails over to the one in its own public subnet."
  value       = local.fallback_nat_gateway_id
}

output "fallback_nat_gateway_ids" {
  description = "NAT gateways the alterNAT instances fail over to."
  value       = local.fallback_nat_gateway_ids
}

output "valid" {
  description = "Whether every alterNAT instance has a public NAT gateway to fail over to."
  value       = local.valid
}

output "error_message" {
  description = "Why the selection is not valid, completing a sentence that starts with the VPC ID."
  value       = local.error_message
}
