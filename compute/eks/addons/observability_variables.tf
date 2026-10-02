################################################################################
# S3-backed metrics and traces
################################################################################

variable "traces_providers" {
  type        = list(string)
  description = "Trace destinations. tempo installs a private S3-backed store and an OTLP collector; [] turns traces off. Applications must be instrumented separately."
  default     = ["tempo"]
  nullable    = false

  validation {
    condition     = alltrue([for provider in var.traces_providers : provider == "tempo"])
    error_message = "traces_providers supports only tempo. Use [] to turn traces off."
  }
}

variable "traces_tempo" {
  type = object({
    retention_days = optional(number, 7)
    s3_bucket_name = optional(string)
    storage_size   = optional(string, "10Gi")
    storage_class  = optional(string)
  })
  description = "Tempo retention and persistent working volume. A null bucket creates a dedicated private encrypted bucket; an existing bucket must be dedicated, in the cluster region, and permit the generated role. Customer-managed KMS grants are not provisioned."
  default     = {}
  nullable    = false

  validation {
    condition     = var.traces_tempo.retention_days >= 1 && floor(var.traces_tempo.retention_days) == var.traces_tempo.retention_days
    error_message = "traces_tempo.retention_days must be a positive whole number of days."
  }

  validation {
    condition     = var.traces_tempo.s3_bucket_name == null ? true : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.traces_tempo.s3_bucket_name))
    error_message = "traces_tempo.s3_bucket_name must be a valid 3-63 character lowercase S3 bucket name, or null to create one."
  }

  validation {
    condition     = can(regex("^[1-9][0-9]*(Mi|Gi|Ti)$", var.traces_tempo.storage_size))
    error_message = "traces_tempo.storage_size must be a positive volume size such as 10Gi."
  }
}

variable "tempo_chart_version" {
  type        = string
  description = "Version of the maintained grafana-community/tempo chart. The default pins Tempo 2.x single-binary architecture. Review configuration before upgrading to Tempo 3.x."
  default     = "2.4.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.tempo_chart_version))
    error_message = "tempo_chart_version must be a semantic version without a leading v."
  }
}

variable "tempo_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into Tempo values (later entries win), for sizing, placement, or other advanced tuning."
  default     = []
  nullable    = false
}

variable "thanos_image" {
  type        = string
  description = "Pinned Thanos image used by the Prometheus sidecar, Query, Store Gateway, and Compactor."
  default     = "quay.io/thanos/thanos:v0.42.4"
  nullable    = false

  validation {
    condition     = length(trimspace(var.thanos_image)) > 0
    error_message = "thanos_image must not be empty."
  }
}

variable "thanos_helm_values" {
  type        = list(string)
  description = "Extra YAML documents for the local Thanos chart, including query/store/compactor resources and placement (later entries win). Compactor must remain a singleton for its bucket."
  default     = []
  nullable    = false
}

variable "otel_traces_collector_helm_values" {
  type        = list(string)
  description = "Extra YAML documents for the OTLP trace collector, including resources, placement, and processors (later entries win)."
  default     = []
  nullable    = false
}
