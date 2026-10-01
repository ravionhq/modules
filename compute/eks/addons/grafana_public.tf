################################################################################
# In-cluster Grafana on the shared public ALB, behind Google sign-in (optional)
#
# Grafana stays a ClusterIP Service; the shared public ALB reaches its pods
# through a target group the load balancer controller binds to that Service,
# the same TargetGroupBinding pattern the EKS workload modules use. The ALB
# routes one hostname to it on the HTTPS listener only.
#
# Anyone on the internet can reach the login page, so sign-in is Google OAuth
# limited to the allowed domains, and Grafana's own login form is turned off.
# The client secret is a Secrets Manager ARN the External Secrets Operator
# materializes into a Kubernetes Secret Grafana reads as an environment
# variable: it is never a Helm value or a Terraform output.
#
# DNS is not managed here. Point the hostname at public_alb_dns_name, and make
# sure one of the HTTPS listener's certificates covers it.
################################################################################

locals {
  grafana_public_enabled = var.grafana_enabled && var.grafana_public_access.enabled

  grafana_hostname          = try(trimspace(var.grafana_public_access.hostname), "")
  grafana_google_client_id  = try(trimspace(var.grafana_public_access.google_client_id), "")
  grafana_google_secret_arn = try(trimspace(var.grafana_public_access.google_client_secret_arn), "")
  grafana_google_domains    = [for domain in var.grafana_public_access.google_allowed_domains : trimspace(domain) if trimspace(domain) != ""]

  grafana_google_secret_name = "ravion-grafana-google-oauth"

  # Target group names are at most 32 characters and cannot end in a hyphen.
  grafana_target_group_name = trimsuffix(substr("${local.name}-grafana", 0, 32), "-")

  grafana_google_oauth_secrets = local.grafana_public_enabled ? [{
    name      = local.grafana_google_secret_name
    namespace = local.grafana_namespace
    template  = {}
    data = [{
      secretKey = "clientSecret"
      remoteRef = local.grafana_google_secret_arn
    }]
  }] : []

  # grafana.ini: SigV4 for the AMP data source always; with public access, the
  # external URL Google redirects back to, Google sign-in, and no login form.
  grafana_public_ini = {
    server = {
      domain   = local.grafana_hostname
      root_url = "https://${local.grafana_hostname}"
    }
    "auth.google" = {
      enabled         = true
      client_id       = local.grafana_google_client_id
      allowed_domains = join(" ", local.grafana_google_domains)
      allow_sign_up   = true
      scopes          = "openid email profile"
      use_pkce        = true
    }
    users = {
      auto_assign_org_role = var.grafana_public_access.google_role
    }
    # The login form being off does not stop the admin password over HTTP
    # basic auth, which would reach the API from the internet.
    "auth.basic" = {
      enabled = false
    }
  }

  # A for expression rather than a conditional: a conditional against {} would
  # unify the sections into a map of strings and quote every boolean.
  grafana_ini = merge(
    {
      auth = merge(
        { sigv4_auth_enabled = true },
        local.grafana_public_enabled ? { disable_login_form = true } : {},
      )
    },
    { for section, settings in local.grafana_public_ini : section => settings if local.grafana_public_enabled },
  )

  # Grafana reads any setting from GF_<SECTION>_<KEY>, so the secret never
  # appears in grafana.ini.
  grafana_env_value_from = local.grafana_public_enabled ? {
    GF_AUTH_GOOGLE_CLIENT_SECRET = {
      secretKeyRef = {
        name = local.grafana_google_secret_name
        key  = "clientSecret"
      }
    }
  } : {}
}

resource "aws_lb_target_group" "grafana" {
  count = local.grafana_public_enabled ? 1 : 0

  name        = local.grafana_target_group_name
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path    = "/api/health"
    matcher = "200"
  }

  tags = local.tags
}

resource "aws_lb_listener_rule" "grafana" {
  count = local.grafana_public_enabled ? 1 : 0

  listener_arn = module.public_alb[0].https_listener_arn
  priority     = var.grafana_public_access.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana[0].arn
  }

  condition {
    host_header {
      values = [local.grafana_hostname]
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.public_alb_creation_enabled && var.public_alb_https_enabled
      error_message = "Grafana's public access needs the shared public ALB with HTTPS on (public_alb_creation_enabled and public_alb_https_enabled). Grafana is never served over plain HTTP."
    }

    precondition {
      condition     = local.grafana_hostname != ""
      error_message = "Grafana's public access needs a hostname, routed on the public ALB's HTTPS listener."
    }

    precondition {
      condition     = local.grafana_google_client_id != "" && local.grafana_google_secret_arn != ""
      error_message = "Grafana's public access needs a Google OAuth client ID and the Secrets Manager ARN of its client secret."
    }

    precondition {
      condition     = length(local.grafana_google_domains) > 0
      error_message = "Grafana's public access needs at least one allowed Google domain; without one, any Google account could sign in."
    }
  }
}

resource "helm_release" "grafana_alb_binding" {
  count = local.grafana_public_enabled ? 1 : 0

  name      = "ravion-grafana-alb-binding"
  namespace = local.grafana_namespace
  chart     = "${path.module}/charts/grafana-alb-binding"

  create_namespace = true
  upgrade_install  = true

  values = [
    yamlencode({
      name           = local.grafana_release_name
      serviceName    = local.grafana_release_name
      servicePort    = 80
      targetGroupArn = aws_lb_target_group.grafana[0].arn
    }),
  ]

  # The TargetGroupBinding CRD comes with the load balancer controller.
  depends_on = [
    helm_release.lb_controller,
    helm_release.grafana,
    aws_lb_listener_rule.grafana,
  ]
}
