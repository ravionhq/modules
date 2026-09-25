################################################################################
# Generated value
#
# Ephemeral: generated during each plan/apply and never written to state or
# plan files. It only reaches AWS through the write-only arguments below, which
# are sent when rotation_version changes.
################################################################################

ephemeral "random_password" "this" {
  length  = var.length
  special = var.special_characters
}
