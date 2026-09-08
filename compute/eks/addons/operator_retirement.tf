# Forget retired Operator resources without deleting live installations or
# revoking credentials during an unrelated add-ons upgrade. See UPGRADE-SSM.md
# for the explicit cutover/uninstall/revocation sequence and legacy provider.
# The custom provider credential MUST be detached separately before upgrading.
# A removed block for it here would require that retired provider on every new
# installation too. See the mandatory state migration in UPGRADE-SSM.md.
removed {
  from = helm_release.ravion_operator
  lifecycle { destroy = false }
}
removed {
  from = helm_release.ravion_operator_credential
  lifecycle { destroy = false }
}
removed {
  from = aws_secretsmanager_secret.ravion_operator_credential
  lifecycle { destroy = false }
}
removed {
  from = aws_secretsmanager_secret_version.ravion_operator_credential
  lifecycle { destroy = false }
}
removed {
  from = helm_release.beacon
  lifecycle { destroy = false }
}
removed {
  from = helm_release.beacon_credential
  lifecycle { destroy = false }
}
removed {
  from = aws_secretsmanager_secret.beacon_credential
  lifecycle { destroy = false }
}
removed {
  from = aws_secretsmanager_secret_version.beacon_credential
  lifecycle { destroy = false }
}
