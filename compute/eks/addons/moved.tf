# Preserve managed-resource state while Terraform-facing resource labels adopt
# Ravion Operator terminology. Runtime Helm release and secret names remain
# unchanged for compatibility with existing clusters.

moved {
  from = aws_secretsmanager_secret.beacon_credential
  to   = aws_secretsmanager_secret.ravion_operator_credential
}

moved {
  from = aws_secretsmanager_secret_version.beacon_credential
  to   = aws_secretsmanager_secret_version.ravion_operator_credential
}

moved {
  from = helm_release.beacon_credential
  to   = helm_release.ravion_operator_credential
}

moved {
  from = helm_release.beacon
  to   = helm_release.ravion_operator
}
