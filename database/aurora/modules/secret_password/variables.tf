variable "secret_id" {
  type        = string
  description = "ARN or name of the secret holding JSON credentials with a password key."
}

variable "version_id" {
  type        = string
  description = "Version of the secret to read. Passing the version a write produced orders the read after that write."
}
