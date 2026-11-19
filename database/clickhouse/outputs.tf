################################################################################
# Connection
################################################################################

output "host" {
  description = "In-cluster DNS name of the Service in front of every ClickHouse server."
  value       = local.service_host
}

output "http_port" {
  description = "ClickHouse HTTP interface port (null when tls_disable_plaintext_ports closes it)."
  value       = local.plaintext_ports_open ? 8123 : null
}

output "native_port" {
  description = "ClickHouse native protocol port (null when tls_disable_plaintext_ports closes it)."
  value       = local.plaintext_ports_open ? 9000 : null
}

output "http_endpoint" {
  description = "In-cluster URL of the HTTP interface (null when tls_disable_plaintext_ports closes it)."
  value       = local.plaintext_ports_open ? "http://${local.service_host}:8123" : null
}

output "https_port" {
  description = "ClickHouse HTTPS interface port (null when TLS is off)."
  value       = var.tls_enabled ? 8443 : null
}

output "secure_native_port" {
  description = "ClickHouse native protocol port over TLS (null when TLS is off)."
  value       = var.tls_enabled ? 9440 : null
}

output "https_endpoint" {
  description = "In-cluster URL of the HTTPS interface (null when TLS is off)."
  value       = var.tls_enabled ? "https://${local.service_host}:8443" : null
}

output "cluster" {
  description = "Name of the ClickHouse cluster, for ON CLUSTER and the cluster() table function."
  value       = local.cluster_layout_name
}

output "database" {
  description = "The database the module created, or null."
  value       = var.database_name
}

output "namespace" {
  description = "Namespace ClickHouse runs in."
  value       = var.namespace
}

output "installation_name" {
  description = "Name of the ClickHouseInstallation resource."
  value       = var.name
}

################################################################################
# TLS
################################################################################

output "tls_enabled" {
  description = "Whether ClickHouse serves TLS on 9440 and 8443."
  value       = var.tls_enabled
}

output "tls_server_name" {
  description = "Name clients verify the server certificate against (null when TLS is off)."
  value       = var.tls_enabled ? local.service_host : null
}

output "tls_ca_secret_name" {
  description = "Kubernetes Secret in the namespace whose ca.crt is the CA clients trust, whichever CA issued it (null when TLS is off). Copy only ca.crt to clients: the Secret also holds the server's private key."
  value       = var.tls_enabled ? local.tls_server_secret : null
}

output "tls_ca_source" {
  description = "Certificate authority behind the server certificate: self_signed, issuer or secret (null when TLS is off)."
  value       = var.tls_enabled ? var.tls_ca_source : null
}

output "tls_issuer" {
  description = "cert-manager issuer that signs the server certificate, as {name, kind, group} (null when TLS is off)."
  value       = var.tls_enabled ? local.tls_issuer_ref : null
}

################################################################################
# Credentials
################################################################################

output "admin_secret_arn" {
  description = "Secrets Manager secret with the admin user's username, password and connection details."
  value       = aws_secretsmanager_secret.user["admin"].arn
}

output "writer_secret_arn" {
  description = "Secrets Manager secret with the writer user's username, password and connection details."
  value       = aws_secretsmanager_secret.user["writer"].arn
}

output "reader_secret_arn" {
  description = "Secrets Manager secret with the reader user's username, password and connection details."
  value       = aws_secretsmanager_secret.user["reader"].arn
}

output "admin_kubernetes_secret_name" {
  description = "Kubernetes Secret in the namespace with the admin user's credentials."
  value       = local.users.admin.secret
}

output "writer_kubernetes_secret_name" {
  description = "Kubernetes Secret in the namespace with the writer user's credentials."
  value       = local.users.writer.secret
}

output "reader_kubernetes_secret_name" {
  description = "Kubernetes Secret in the namespace with the reader user's credentials."
  value       = local.users.reader.secret
}

################################################################################
# S3
################################################################################

output "s3_bucket_name" {
  description = "Bucket holding backups and the cold tier, or null when neither is on."
  value       = local.s3_bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the bucket holding backups and the cold tier, or null."
  value       = local.s3_bucket_arn
}

output "iam_role_arn" {
  description = "IAM role the ClickHouse pods use for S3 through EKS Pod Identity, or null."
  value       = local.s3_enabled ? aws_iam_role.clickhouse[0].arn : null
}

output "backup_enabled" {
  description = "Whether scheduled backups run."
  value       = var.backup_enabled
}

output "cold_storage_policy" {
  description = "Storage policy whose cold volume is S3, or null when the cold tier is off."
  value       = var.cold_storage_enabled ? "tiered" : null
}
