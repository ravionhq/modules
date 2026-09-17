################################################################################
# Pod Identity
#
# The workload's IAM role and the EKS Pod Identity association that binds it to
# the release's ServiceAccount. Everything asserted here is known at plan time
# against mocked providers: the role name, the trust policy, the attached
# policies, and the association's target.
################################################################################

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_region" {
    defaults = {
      id     = "us-east-1"
      name   = "us-east-1"
      region = "us-east-1"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  # The association validates role_arn as an ARN at plan time, so the mocked
  # role must produce one rather than the provider's random string.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/acme-prod-api-task"
    }
  }
}

variables {
  name              = "api"
  region            = "us-east-1"
  vpc_id            = "vpc-0123456789abcdef0"
  listener_arn      = null
  cluster_name      = "acme-prod"
  release_name      = "api"
  release_namespace = "acme"
}

run "disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role.pod_identity) == 0 && length(aws_eks_pod_identity_association.this) == 0
    error_message = "A workload that does not ask for an AWS identity must get no role and no association."
  }

  assert {
    condition     = output.pod_identity_role_arn == null && output.pod_identity_role_name == null && output.pod_identity_service_account_name == null && output.pod_identity_association_id == null
    error_message = "Every Pod Identity output must be null when the role is disabled."
  }
}

run "binds_a_cluster_pinned_role_to_the_release_service_account" {
  command = plan

  variables {
    pod_identity_role_creation_enabled = true
  }

  assert {
    condition     = aws_iam_role.pod_identity[0].name == "acme-prod-api-task" && output.pod_identity_role_name == "acme-prod-api-task"
    error_message = "The default role name must be <cluster_name>-<name>-task so it is unique per cluster and distinct from the ECS <name>-task role."
  }

  assert {
    condition     = jsondecode(aws_iam_role.pod_identity[0].assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "The role must trust the EKS Pod Identity service principal."
  }

  assert {
    condition     = tolist(sort(jsondecode(aws_iam_role.pod_identity[0].assume_role_policy).Statement[0].Action)) == tolist(["sts:AssumeRole", "sts:TagSession"])
    error_message = "Pod Identity needs sts:AssumeRole and sts:TagSession (the agent tags sessions with the pod identity)."
  }

  assert {
    condition     = jsondecode(aws_iam_role.pod_identity[0].assume_role_policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == "arn:aws:eks:us-east-1:123456789012:cluster/acme-prod"
    error_message = "The trust policy must be pinned to this cluster's ARN so an association in another cluster cannot use the role."
  }

  assert {
    condition     = jsondecode(aws_iam_role.pod_identity[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "The trust policy must be pinned to this account."
  }

  assert {
    condition     = aws_eks_pod_identity_association.this[0].cluster_name == "acme-prod" && aws_eks_pod_identity_association.this[0].namespace == "acme" && aws_eks_pod_identity_association.this[0].service_account == "api"
    error_message = "The association must target the release's ServiceAccount (named after the release) in the release namespace on the workload's cluster."
  }

  assert {
    condition     = output.pod_identity_service_account_name == "api"
    error_message = "The ServiceAccount output must name the association target."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.pod_identity_managed) == 0 && length(aws_iam_role_policy.pod_identity_inline) == 0
    error_message = "A role with no policies configured must carry no permissions."
  }
}

run "attaches_managed_and_inline_policies" {
  command = plan

  variables {
    pod_identity_role_creation_enabled = true
    pod_identity_managed_policy_arns   = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
    pod_identity_inline_policies = {
      read-bucket = {
        Version = "2012-10-17"
        Statement = [{
          Sid      = "ReadBucket"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = "arn:aws:s3:::my-bucket/*"
        }]
      }
    }
  }

  assert {
    condition     = aws_iam_role_policy_attachment.pod_identity_managed["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"].policy_arn == "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    error_message = "Each managed policy ARN must be attached to the role."
  }

  assert {
    condition     = aws_iam_role_policy.pod_identity_inline["read-bucket"].name == "read-bucket" && jsondecode(aws_iam_role_policy.pod_identity_inline["read-bucket"].policy).Statement[0].Action[0] == "s3:GetObject"
    error_message = "Each inline policy must be attached under its key with its document encoded as JSON."
  }
}

run "honours_explicit_role_and_service_account_names" {
  command = plan

  variables {
    pod_identity_role_creation_enabled = true
    pod_identity_role_name             = "api-pods"
    pod_identity_service_account_name  = "api-sa"
  }

  assert {
    condition     = aws_iam_role.pod_identity[0].name == "api-pods"
    error_message = "An explicit pod_identity_role_name must replace the derived default."
  }

  assert {
    condition     = aws_eks_pod_identity_association.this[0].service_account == "api-sa"
    error_message = "An explicit pod_identity_service_account_name must replace the release name."
  }
}

run "rejects_a_role_without_a_cluster_identity" {
  command = plan

  variables {
    pod_identity_role_creation_enabled = true
    cluster_name                       = null
  }

  expect_failures = [var.pod_identity_role_creation_enabled]
}

run "rejects_a_role_without_a_service_account" {
  command = plan

  variables {
    pod_identity_role_creation_enabled = true
    release_name                       = null
  }

  expect_failures = [var.pod_identity_role_creation_enabled]
}

run "rejects_a_derived_role_name_over_the_iam_limit" {
  command = plan

  variables {
    pod_identity_role_creation_enabled = true
    cluster_name                       = "a-cluster-name-that-is-already-quite-long-for-an-iam-role-prefix"
    name                               = "and-a-workload-name-to-match"
  }

  expect_failures = [aws_iam_role.pod_identity]
}
