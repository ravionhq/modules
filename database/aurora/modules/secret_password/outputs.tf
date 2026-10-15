output "password" {
  description = "The password key of the secret's JSON. Ephemeral: usable only in write-only arguments and other ephemeral contexts."
  value       = jsondecode(ephemeral.aws_secretsmanager_secret_version.this.secret_string).password
  ephemeral   = true
}
