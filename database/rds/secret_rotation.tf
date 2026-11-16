################################################################################
# Master User Secret Rotation
################################################################################

# RDS rotates the managed master user secret every seven days by default,
# which breaks apps that read the password only at startup. Rotation is off
# unless master_user_secret_rotation_enabled is true; rotation_enabled = false
# cancels the rotation that RDS configures (AWS provider >= 6.62.0). rotate_immediately = false keeps
# applies from changing the password outside the rotation schedule.
resource "aws_secretsmanager_secret_rotation" "master_user" {
  count = var.master_user_password_management_enabled ? 1 : 0

  secret_id          = aws_db_instance.this.master_user_secret[0].secret_arn
  rotation_enabled   = var.master_user_secret_rotation_enabled
  rotate_immediately = false

  dynamic "rotation_rules" {
    for_each = var.master_user_secret_rotation_enabled ? [1] : []

    content {
      automatically_after_days = var.master_user_secret_rotation_days
    }
  }
}
