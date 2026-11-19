# Ravion AWS account setup. See README.md.
#
# The IAM roles, policies and OIDC provider are in iam.gen.tf.json, which
# Ravion generates from the same source as its CloudFormation template, so
# both grant exactly the same permissions. Do not edit that file.
#
# This file reports the setup to Ravion, which is what CloudFormation's
# authenticator does for the template: Ravion records the roles and their
# version, then checks it can assume each role before using it.

data "aws_caller_identity" "current" {
  count = var.send_callback ? 1 : 0
}

locals {
  callback_body = var.send_callback ? jsonencode({
    event                = "apply"
    ravion_id            = var.ravion_id
    aws_account_id       = data.aws_caller_identity.current[0].account_id
    role_arn             = aws_iam_role.role.arn
    deployments_role_arn = try(aws_iam_role.deployments_role[0].arn, "")
    terraform_role_arn   = try(aws_iam_role.terraform_role[0].arn, "")
    sandboxes_role_arn   = try(aws_iam_role.sandboxes_role[0].arn, "")
    role_version         = local.ravion_role_version
  }) : ""
}

resource "terraform_data" "callback" {
  count = var.send_callback ? 1 : 0

  # Reports again when the roles change, when any role's permissions or trust
  # change, and when a new onboarding token is supplied: applying with a fresh
  # token from Ravion is how to ask Ravion to check the roles again.
  triggers_replace = [
    local.callback_body,
    sha256(jsonencode(local.ravion_policy_documents)),
    sha256(var.onboarding_token),
  ]

  provisioner "local-exec" {
    command = "curl --fail-with-body --silent --show-error --retry 5 --retry-all-errors --retry-delay 5 -X POST \"$RAVION_CALLBACK_URL\" -H \"Authorization: Bearer $RAVION_ONBOARDING_TOKEN\" -H 'Content-Type: application/json' --data \"$RAVION_CALLBACK_BODY\""
    environment = {
      RAVION_CALLBACK_URL     = var.callback_url
      RAVION_CALLBACK_BODY    = local.callback_body
      RAVION_ONBOARDING_TOKEN = var.onboarding_token
    }
  }

  depends_on = [
    aws_iam_role_policy.role_ravion_policy,
    aws_iam_role_policy.deployments_role_ravion_policy,
    aws_iam_role_policy.terraform_role_ravion_policy,
    aws_iam_role_policy.sandboxes_role_ravion_policy,
    aws_iam_role_policy_attachment.role_managed_policy_broker,
    aws_iam_role_policy_attachment.role_managed_policy_deploy,
    aws_iam_role_policy_attachment.role_managed_policy_deploy2,
    aws_iam_role_policy_attachment.deployments_role_deployments_policy,
    aws_iam_role_policy_attachment.deployments_role_deployments_policy2,
    aws_iam_role_policy_attachment.terraform_role_terraform_policy,
    aws_iam_role_policy_attachment.sandboxes_role_sandboxes_policy,
    aws_iam_role_policy_attachment.sandboxes_role_sandboxes_policy2,
  ]
}

# On terraform destroy, tells Ravion the roles are going away before they are
# deleted, so it stops using them. Best effort: destroy continues if Ravion
# cannot be reached or the token has expired. The values live in input,
# because a destroy-time provisioner can only read its own resource; a new
# token updates input in place without replacing it.
resource "terraform_data" "disconnect" {
  count = var.send_callback ? 1 : 0

  input = {
    url   = var.callback_url
    token = var.onboarding_token
    body = jsonencode({
      event     = "destroy"
      ravion_id = var.ravion_id
    })
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "curl --fail-with-body --silent --show-error --retry 3 --retry-delay 5 -X POST \"$RAVION_CALLBACK_URL\" -H \"Authorization: Bearer $RAVION_ONBOARDING_TOKEN\" -H 'Content-Type: application/json' --data \"$RAVION_CALLBACK_BODY\""
    environment = {
      RAVION_CALLBACK_URL     = self.input.url
      RAVION_CALLBACK_BODY    = self.input.body
      RAVION_ONBOARDING_TOKEN = self.input.token
    }
  }

  # Destroyed before the roles, so Ravion hears first.
  depends_on = [terraform_data.callback, aws_iam_role.role]
}
