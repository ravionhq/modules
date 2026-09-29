################################################################################
# Deploy SSM Document
#
# The aws:ec2 deploy contract. The deploy manager runs this document
# against the group's instances (batched, with per-instance status). The
# same document is run on scale-out instances to catch them up to the
# current release.
#
# Container runtime: the document takes imageUri (the full image URI to
# run), installs a supervisord program for it, and encodes the whole
# in-place deploy.
#
# Manual runtime: the document takes commands (the service's deploy
# command list). Before running them it stops the prior app and rebuilds
# the app env file. Afterward it starts the configured long-running app
# command under supervisord.
#
# NAMING CONTRACT: the document name is derived by the platform as
# "<autoscaling_group_name>-deploy". Use the actual group name, which can
# be fixed or generated, so replacements keep this contract with the
# platform's Ec2DeployDocumentName.
################################################################################

resource "aws_ssm_document" "deploy" {
  name            = "${module.autoscaling.autoscaling_group_name}-deploy"
  document_type   = "Command"
  document_format = "YAML"

  content = local.container_runtime ? yamlencode({
    schemaVersion = "2.2"
    description   = "In-place supervised container deploy for the ${var.name} EC2 service."

    parameters = {
      imageUri = {
        type           = "String"
        description    = "Full container image URI to deploy, including tag or digest."
        allowedPattern = "^[^\\s]+$"
      }
      deployId = {
        type           = "String"
        description    = "Identifier for this deploy, used for release directories and logging."
        default        = ""
        allowedPattern = "^[A-Za-z0-9._-]*$"
      }
    }

    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deploy"
        inputs = {
          timeoutSeconds = tostring(var.deploy_timeout_seconds)
          runCommand     = [local.deploy_script]
        }
      }
    ]
    }) : yamlencode({
    schemaVersion = "2.2"
    description   = "Manual deploy for the ${var.name} EC2 service: prepares the release, then runs the app under supervisord."

    parameters = {
      commands = {
        type        = "String"
        description = "Release preparation script to run on the instance with the app env file loaded."
      }
      deployId = {
        type           = "String"
        description    = "Identifier for this deploy, used for logging."
        default        = ""
        allowedPattern = "^[A-Za-z0-9._-]*$"
      }
      sourceRepo = {
        type           = "String"
        description    = "Optional Git repository URL to check out before running the manual deploy commands."
        default        = ""
        allowedPattern = "^[A-Za-z0-9:/@._+-]*$"
      }
      sourceBranch = {
        type           = "String"
        description    = "Optional Git branch to check out."
        default        = ""
        allowedPattern = "^[A-Za-z0-9._/@:+-]*$"
      }
      sourceRef = {
        type           = "String"
        description    = "Optional immutable Git ref to check out."
        default        = ""
        allowedPattern = "^[A-Za-z0-9._/@:+-]*$"
      }
      sourceBasePath = {
        type           = "String"
        description    = "Repository-relative working directory for the deploy and start commands."
        default        = "."
        allowedPattern = "^[A-Za-z0-9._/-]*$"
      }
      gitTokenParameterName = {
        type           = "String"
        description    = "Optional SSM SecureString parameter containing the temporary Git credential."
        default        = ""
        allowedPattern = "^(|/ravion/git-tokens/ec2/[A-Za-z0-9._/-]+)$"
      }
    }

    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deploy"
        inputs = {
          timeoutSeconds = tostring(var.deploy_timeout_seconds)
          runCommand = [join("\n", [
            local.manual_deploy_prelude,
            "{{ commands }}",
            local.manual_deploy_postlude,
          ])]
        }
      }
    ]
  })

  tags = local.tags
}
