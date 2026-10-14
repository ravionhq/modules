mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_resource {
    target = aws_iam_instance_profile.instance
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/supervised-app-instance"
    }
  }

  override_resource {
    target = module.instance_security_group.aws_security_group.this
    values = {
      id = "sg-12345678"
    }
  }

  override_resource {
    target = aws_launch_template.app
    values = {
      id = "lt-12345678"
    }
  }

  override_resource {
    target = aws_lb_target_group.app
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/supervised-app/1234567890abcdef"
    }
  }
}

variables {
  name          = "supervised-app"
  region        = "us-east-1"
  vpc_id        = "vpc-12345678"
  subnet_ids    = ["subnet-12345678"]
  instance_type = "t3.micro"
  ami_id        = "ami-12345678"
}

run "existing_group_and_document_names_remain_unchanged" {
  command = plan

  variables {
    runtime = "container"
  }

  assert {
    condition     = output.autoscaling_group_name == "supervised-app" && aws_ssm_document.deploy.name == "supervised-app-deploy"
    error_message = "An ordinary upgrade must preserve the existing group and deploy document names."
  }
}

run "deploy_document_follows_the_generated_group_name" {
  command = plan

  variables {
    runtime                                  = "container"
    autoscaling_group_generated_name_enabled = true
  }

  override_resource {
    target = module.autoscaling.aws_autoscaling_group.this
    values = {
      name = "supervised-app-unique-suffix"
    }
  }

  assert {
    condition     = aws_ssm_document.deploy.name == "${output.autoscaling_group_name}-deploy" && aws_ssm_document.deploy.name == "supervised-app-unique-suffix-deploy"
    error_message = "The deploy document must use the generated group name rather than the stable service name."
  }
}

run "container_is_supervised_and_logs_per_deployment" {
  command = plan

  variables {
    runtime = "container"
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "autorestart=true")
    error_message = "Container deploys must configure supervisord to restart the app."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "deployment/$${DEPLOY_ID}/instance/{instance_id}")
    error_message = "Container logs must use deployment- and instance-scoped CloudWatch streams."
  }

  assert {
    condition     = strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "exec > >(tee -a \"$LOG_PATH\") 2> >(tee -a \"$LOG_PATH\" >&2)")
    error_message = "Container SSM stdout and stderr must also be copied to the deployment instance log."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "supervisor==4.3.0")
    error_message = "Instances must install the pinned Supervisor version at bootstrap."
  }

  assert {
    condition     = strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "export HOME=\"$${HOME:-/root}\"")
    error_message = "Container deploys must restore root-shell HOME for the release and runner scripts."
  }

  assert {
    condition     = output.log_stream_prefix == "deployment"
    error_message = "The log stream output must select all deployment-scoped streams."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "stdout_logfile_maxbytes=20MB") && strcontains(aws_ssm_document.deploy.content, "stdout_logfile_backups=5")
    error_message = "Container deploys must bound the app log with nonzero Supervisor rotation settings."
  }

  assert {
    condition     = !strcontains(aws_ssm_document.deploy.content, "stdout_logfile_maxbytes=0")
    error_message = "Rotation must never be disabled for the app log."
  }

  assert {
    condition = alltrue([
      for setting in ["stopsignal=TERM", "stopwaitsecs=30", "stopasgroup=true", "killasgroup=true", "redirect_stderr=true"] :
      strcontains(aws_ssm_document.deploy.content, setting)
    ])
    error_message = "Rotation must not disturb the existing shutdown and stream-merging behavior."
  }

}

run "log_rotation_settings_are_configurable" {
  command = plan

  variables {
    runtime                   = "container"
    log_rotation_max_size_mb  = 50
    log_rotation_backup_count = 2
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "stdout_logfile_maxbytes=50MB") && strcontains(aws_ssm_document.deploy.content, "stdout_logfile_backups=2")
    error_message = "Configured rotation settings must reach the generated Supervisor program config."
  }
}

run "log_rotation_rejects_disabling_rotation" {
  command = plan

  variables {
    runtime                  = "container"
    log_rotation_max_size_mb = 0
  }

  expect_failures = [var.log_rotation_max_size_mb]
}

run "log_rotation_rejects_fractional_values" {
  command = plan

  variables {
    runtime                   = "container"
    log_rotation_max_size_mb  = 1.5
    log_rotation_backup_count = 2.5
  }

  expect_failures = [
    var.log_rotation_max_size_mb,
    var.log_rotation_backup_count,
  ]
}

run "manual_start_command_is_supervised" {
  command = plan

  variables {
    runtime              = "manual"
    manual_start_command = "cd /srv/app && ./bin/server"
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, base64encode("cd /srv/app && ./bin/server"))
    error_message = "The manual start command must be embedded safely in the deploy document."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "exec /bin/bash -lc")
    error_message = "Manual deploys must run the long-lived start command through the supervisor runner."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "autorestart=true")
    error_message = "Manual deploys must configure supervisord to restart the app."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "sourceRepo") && strcontains(aws_ssm_document.deploy.content, "gitTokenParameterName")
    error_message = "Manual deploys must expose the optional nested source transport parameters."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "dnf install -y git jq unzip")
    error_message = "Instances must install Git at bootstrap for source-backed manual deploys."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "GIT_ASKPASS") && strcontains(aws_ssm_document.deploy.content, "SOURCE_DIRECTORY=\"$SOURCE_ROOT/source\"")
    error_message = "Manual deploys must authenticate transiently and check source out under the Ravion-managed directory."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "if ! command -v git") && strcontains(aws_ssm_document.deploy.content, "dnf install -y git")
    error_message = "Source-backed manual deploys must install Git on existing instances before checkout."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "source-working-directory")
    error_message = "Manual deploy and start commands must share the selected source working directory."
  }

  assert {
    condition     = strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "export HOME=\"$${HOME:-/root}\"")
    error_message = "Manual deploy commands and the supervised start command must run with root-shell HOME."
  }

  assert {
    condition     = strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "then export TERM=xterm; fi")
    error_message = "Manual deploy commands must run with a usable TERM instead of the SSM agent's dumb terminal."
  }

  assert {
    condition     = strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "exec > >(tee -a \"$LOG_PATH\") 2> >(tee -a \"$LOG_PATH\" >&2)")
    error_message = "Manual SSM stdout and stderr must also be copied to the deployment instance log."
  }

  assert {
    condition     = yamldecode(aws_ssm_document.deploy.content).parameters.commands.type == "String"
    error_message = "Manual deploy commands must use a String parameter so the command script can be embedded between the prelude and postlude."
  }

  assert {
    condition     = length(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand) == 1 && strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "{{ commands }}")
    error_message = "Manual deploy setup, commands, and teardown must be one runCommand string so SSM does not create a nested command array during parameter substitution."
  }
}

run "web_target_group_supports_slow_start_stickiness_and_direct_access" {
  command = plan

  variables {
    runtime                         = "container"
    app_port                        = 3000
    deploy_health_check_path        = "/health"
    health_check_grace_period       = 450
    load_balancer_security_group_id = "sg-87654321"
    direct_access_cidr_blocks       = ["10.0.0.0/8"]
    load_balancer_attachment = {
      creation_enabled = true
      target_group = {
        port       = 3000
        slow_start = 60
        stickiness = {
          enabled         = true
          type            = "app_cookie"
          cookie_duration = 3600
          cookie_name     = "SESSION_ID"
        }
      }
      listener_rules = []
    }
  }

  assert {
    condition     = aws_lb_target_group.app[0].slow_start == 60
    error_message = "The target group must receive the configured slow start duration."
  }

  assert {
    condition     = aws_lb_target_group.app[0].stickiness[0].type == "app_cookie" && aws_lb_target_group.app[0].stickiness[0].cookie_name == "SESSION_ID" && aws_lb_target_group.app[0].stickiness[0].cookie_duration == 3600
    error_message = "The target group must receive application-cookie stickiness settings."
  }

}

run "slow_start_rejects_values_below_30_seconds" {
  command = plan

  variables {
    runtime                  = "container"
    app_port                 = 3000
    deploy_health_check_path = "/health"
    load_balancer_attachment = {
      creation_enabled = true
      target_group = {
        port       = 3000
        slow_start = 29
      }
      listener_rules = []
    }
  }

  expect_failures = [var.load_balancer_attachment]
}
