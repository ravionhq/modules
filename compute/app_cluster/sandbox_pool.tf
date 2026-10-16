################################################################################
# Sandbox Pool
#
# Registers the execution environment whose sandbox pool runs the cluster's
# apps. Ravion then sets up the pool's host role, chunk store and launch
# templates, and launches hosts in the subnet and security group below when
# apps need room. The pool belongs to this module instance: the provider
# authenticates with the stack run's credentials, and Ravion refuses to delete
# the pool while it still runs sandboxes.
################################################################################

resource "ravion_sandbox_pool" "this" {
  aws_account_id    = var.ravion_aws_account_id
  region            = local.region
  vpc_id            = var.vpc_id
  subnet_id         = var.host_subnet_id
  security_group_id = aws_security_group.sandbox_hosts.id

  # Empty lets Ravion choose the hosts' instance types.
  instance_types = var.host_instance_types
  capacity_types = var.host_capacity_types
  reserve_policy = var.host_reserve_policy
  max_hosts      = var.max_hosts
}
