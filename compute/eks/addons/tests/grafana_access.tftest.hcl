################################################################################
# In-cluster Grafana on a shared ALB, behind Google sign-in
################################################################################

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/app/mock/0123456789abcdef" }
  }
  mock_resource "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:listener/app/mock/0123456789abcdef/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/mock/0123456789abcdef" }
  }
  mock_resource "aws_prometheus_workspace" {
    defaults = {
      id  = "ws-11111111-2222-3333-4444-555555555555"
      arn = "arn:aws:aps:us-east-2:123456789012:workspace/ws-11111111-2222-3333-4444-555555555555"
    }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      vpc_config = [{
        vpc_id                    = "vpc-12345678"
        cluster_security_group_id = "sg-12345678"
        control_plane_egress_mode = ""
        endpoint_private_access   = true
        endpoint_public_access    = false
        public_access_cidrs       = []
        security_group_ids        = []
        subnet_ids                = []
      }]
    }
  }
}

mock_provider "helm" {}
mock_provider "ravion" {}

variables {
  cluster_name                = "test-cluster"
  region                      = "us-east-2"
  cluster_security_group_id   = "sg-12345678"
  public_subnet_ids           = ["subnet-0a", "subnet-0b"]
  node_subnet_ids             = ["subnet-1a", "subnet-1b"]
  public_alb_creation_enabled = true
  public_alb_https_enabled    = true
  public_alb_certificate_arns = ["arn:aws:acm:us-east-2:123456789012:certificate/11111111-2222-3333-4444-555555555555"]
  karpenter_enabled           = false
  eso_enabled                 = true
  eso_allowed_namespaces      = ["apps"]
  logs_providers              = ["loki"]
  metrics_providers           = ["prometheus"]
  traces_providers            = ["tempo"]
  ravion_operator_enabled     = false
  grafana_enabled             = true
  grafana_access = {
    enabled                  = true
    hostname                 = "grafana.example.com"
    google_client_id         = "1234.apps.googleusercontent.com"
    google_client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-google-AbCdEf"
    google_allowed_domains   = ["example.com"]
  }
}

run "in_cluster_only_by_default" {
  command = plan

  variables {
    grafana_access = {}
  }

  assert {
    condition     = length(aws_lb_target_group.grafana) == 0 && length(aws_lb_listener_rule.grafana) == 0 && length(helm_release.grafana_alb_binding) == 0 && output.grafana_url == null
    error_message = "Grafana must stay in-cluster unless load balancer access is on"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"].auth == { sigv4_auth_enabled = true } && !contains(keys(yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]), "auth.google") && !contains(keys(yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]), "auth.basic")
    error_message = "Grafana without load balancer access must keep its login form and have no Google sign-in"
  }
}

run "routes_the_hostname_on_the_public_alb_https_listener" {
  command = plan

  assert {
    condition     = aws_lb_listener_rule.grafana[0].listener_arn == module.public_alb[0].https_listener_arn
    error_message = "Grafana must be routed on the HTTPS listener"
  }

  assert {
    condition     = one(one(aws_lb_listener_rule.grafana[0].condition).host_header).values == toset(["grafana.example.com"])
    error_message = "Only Grafana's hostname may route to it"
  }

  assert {
    condition     = aws_lb_target_group.grafana[0].port == 3000 && aws_lb_target_group.grafana[0].target_type == "ip" && one(aws_lb_target_group.grafana[0].health_check).path == "/api/health" && aws_lb_target_group.grafana[0].name == "test-cluster-grafana"
    error_message = "The target group must register Grafana's pods on 3000 and check /api/health"
  }

  assert {
    condition     = yamldecode(helm_release.grafana_alb_binding[0].values[0]).serviceName == "ravion-grafana" && yamldecode(helm_release.grafana_alb_binding[0].values[0]).servicePort == 80
    error_message = "The binding must point at Grafana's Service"
  }

  assert {
    condition     = output.grafana_url == "https://grafana.example.com"
    error_message = "The Grafana URL must be the hostname over HTTPS"
  }
}

run "signs_in_with_google_for_allowed_domains_only" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.google"].enabled == true && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.google"].client_id == "1234.apps.googleusercontent.com" && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.google"].allowed_domains == "example.com"
    error_message = "Google sign-in must be on, for the allowed domains"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"].auth.disable_login_form == true && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"].server.root_url == "https://grafana.example.com" && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"].users.auto_assign_org_role == "Viewer"
    error_message = "Grafana behind a load balancer must drop the login form, know its external URL, and make Google users Viewers by default"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.basic"].enabled == false
    error_message = "Grafana behind a load balancer must refuse the admin password over HTTP basic auth"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0]).envValueFrom.GF_AUTH_GOOGLE_CLIENT_SECRET.secretKeyRef.name == "ravion-grafana-google-oauth" && !strcontains(helm_release.grafana[0].values[0], "client_secret")
    error_message = "The client secret must come from a Kubernetes Secret, never a Helm value"
  }

  assert {
    condition     = contains([for secret in yamldecode(helm_release.observability_secrets[0].values[0]).externalSecrets : secret.name], "ravion-grafana-google-oauth")
    error_message = "External Secrets must materialize the Google client secret"
  }

  assert {
    condition     = yamldecode(helm_release.external_secrets_stores[0].values[0]).allowedNamespaces == ["apps", "ravion-operator"]
    error_message = "The secret store must admit Grafana's namespace beside the workload allow-list"
  }
}

run "rejects_plain_http" {
  command = plan

  variables {
    public_alb_https_enabled    = false
    public_alb_certificate_arns = []
  }

  expect_failures = [aws_lb_listener_rule.grafana]
}

run "rejects_no_allowed_domains" {
  command = plan

  variables {
    grafana_access = {
      enabled                  = true
      hostname                 = "grafana.example.com"
      google_client_id         = "1234.apps.googleusercontent.com"
      google_client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-google-AbCdEf"
    }
  }

  expect_failures = [aws_lb_listener_rule.grafana]
}

run "rejects_no_hostname" {
  command = plan

  variables {
    grafana_access = {
      enabled                  = true
      google_client_id         = "1234.apps.googleusercontent.com"
      google_client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-google-AbCdEf"
      google_allowed_domains   = ["example.com"]
    }
  }

  expect_failures = [aws_lb_listener_rule.grafana]
}

run "rejects_unknown_role" {
  command = plan

  variables {
    grafana_access = {
      enabled     = true
      google_role = "Owner"
    }
  }

  expect_failures = [var.grafana_access]
}

run "rejects_no_client_secret" {
  command = plan

  variables {
    grafana_access = {
      enabled                = true
      hostname               = "grafana.example.com"
      google_client_id       = "1234.apps.googleusercontent.com"
      google_allowed_domains = ["example.com"]
    }
  }

  expect_failures = [aws_lb_listener_rule.grafana]
}

run "rejects_without_external_secrets" {
  command = plan

  variables {
    eso_enabled = false
  }

  expect_failures = [helm_release.observability_secrets]
}

run "routes_the_hostname_on_the_private_alb_https_listener" {
  command = plan

  override_module {
    target = module.private_alb
    outputs = {
      alb_arn            = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/app/private/0123456789abcdef"
      alb_arn_suffix     = "app/private/0123456789abcdef"
      alb_dns_name       = "internal-private-123.us-east-2.elb.amazonaws.com"
      alb_zone_id        = "Z3AADJGX6KTTL2"
      http_listener_arn  = "arn:aws:elasticloadbalancing:us-east-2:123456789012:listener/app/private/0123456789abcdef/http"
      https_listener_arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:listener/app/private/0123456789abcdef/https"
      security_group_id  = "sg-private"
    }
  }

  variables {
    private_alb_creation_enabled = true
    private_alb_https_enabled    = true
    private_alb_certificate_arns = ["arn:aws:acm:us-east-2:123456789012:certificate/66666666-7777-8888-9999-000000000000"]
    grafana_access = {
      enabled                  = true
      load_balancer            = "private"
      hostname                 = "grafana.internal.example.com"
      google_client_id         = "1234.apps.googleusercontent.com"
      google_client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-google-AbCdEf"
      google_allowed_domains   = ["example.com"]
    }
  }

  assert {
    condition     = aws_lb_listener_rule.grafana[0].listener_arn == "arn:aws:elasticloadbalancing:us-east-2:123456789012:listener/app/private/0123456789abcdef/https"
    error_message = "A private Grafana must be routed on the private ALB's HTTPS listener"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.google"].enabled == true && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.basic"].enabled == false && output.grafana_url == "https://grafana.internal.example.com"
    error_message = "A private Grafana must still sign in with Google only"
  }
}

run "rejects_private_without_the_private_alb" {
  command = plan

  variables {
    grafana_access = {
      enabled                  = true
      load_balancer            = "private"
      hostname                 = "grafana.internal.example.com"
      google_client_id         = "1234.apps.googleusercontent.com"
      google_client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-google-AbCdEf"
      google_allowed_domains   = ["example.com"]
    }
  }

  expect_failures = [aws_lb_listener_rule.grafana]
}

run "rejects_unknown_load_balancer" {
  command = plan

  variables {
    grafana_access = {
      enabled       = true
      load_balancer = "internal"
    }
  }

  expect_failures = [var.grafana_access]
}
