################################################################################
# In-cluster Grafana environment variables
#
# The two inputs an EKS workload has, in the same shapes:
# grafana_environment_variables is plain {name, value}, and grafana_secrets is
# {name, value_from} references. The External Secrets Operator reads every
# reference in the cluster into one Kubernetes Secret, and Grafana reads that
# as environment variables: a referenced value is never a Helm value, a
# grafana.ini line or a Terraform output.
#
# Grafana reads any setting from GF_<SECTION>_<KEY>, which is how a sign-in
# provider's client comes from here: GF_AUTH_<PROVIDER>_CLIENT_ID and
# GF_AUTH_<PROVIDER>_CLIENT_SECRET.
################################################################################

locals {
  grafana_environment_variables = [for variable in var.grafana_environment_variables : variable if var.grafana_enabled]
  grafana_secrets               = [for secret in var.grafana_secrets : secret if var.grafana_enabled]

  grafana_env = { for variable in local.grafana_environment_variables : variable.name => variable.value }

  # A Secrets Manager ARN may end in ECS's extraction suffix,
  # secret:<name>:<json key>:<version stage>:<version id>. Neither a secret's
  # name nor a parameter's holds a colon, so the ARN itself is the first seven
  # fields for Secrets Manager and all six for Parameter Store.
  grafana_secret_fields = [
    for secret in local.grafana_secrets : {
      name   = secret.name
      fields = split(":", trimspace(secret.value_from))
    }
  ]

  # What an ExternalSecret's remoteRef takes for each reference. External
  # Secrets writes a version id as uuid/<id> and a version stage as it is. The
  # release's own store is Secrets Manager's, so only a parameter names its store.
  grafana_secret_remote_refs = [
    for secret in local.grafana_secret_fields : {
      secretKey = secret.name
      remoteRef = join(":", slice(secret.fields, 0, min(7, length(secret.fields))))
      property  = try(secret.fields[7], "")
      version   = try(secret.fields[9], "") != "" ? "uuid/${secret.fields[9]}" : try(secret.fields[8], "")
      storeName = try(secret.fields[2], "") == "ssm" ? var.eso_parameter_store_store_name : ""
    }
  ]

  grafana_env_secret_name = "ravion-grafana-env"

  grafana_env_secrets = length(local.grafana_secrets) == 0 ? [] : [{
    name      = local.grafana_env_secret_name
    namespace = local.grafana_namespace
    template  = {}
    data      = local.grafana_secret_remote_refs
  }]

  grafana_env_value_from = merge(
    local.grafana_auth_env_value_from,
    {
      for secret in local.grafana_secrets : secret.name => {
        secretKeyRef = {
          name = local.grafana_env_secret_name
          key  = secret.name
        }
      }
    },
  )

  grafana_secret_names = [for secret in local.grafana_secrets : secret.name]
  grafana_env_names    = concat([for variable in local.grafana_environment_variables : variable.name], local.grafana_secret_names)

  # The environment variables that give Grafana a value: every secret, and a
  # plain variable unless it is left blank.
  grafana_env_names_with_a_value = concat(
    [for variable in local.grafana_environment_variables : variable.name if trimspace(variable.value) != ""],
    local.grafana_secret_names,
  )

  # Each environment variable is set in one place. A sign-in provider's client
  # written on the provider reaches Grafana under its GF_AUTH_ names too.
  grafana_env_set_twice = distinct([
    for name in local.grafana_env_names : name if(
      length([for other in local.grafana_env_names : other if other == name]) > 1 ||
      contains(local.grafana_auth_client_env_names, name)
    )
  ])
}
