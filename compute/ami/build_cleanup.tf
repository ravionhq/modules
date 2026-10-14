resource "terraform_data" "build_cleanup" {
  # Destroy dependents first, while the build infrastructure still exists.
  depends_on = [
    aws_imagebuilder_component.this,
    aws_imagebuilder_infrastructure_configuration.this,
    aws_imagebuilder_distribution_configuration.this,
  ]

  # No replacement triggers: changing component content must never run cleanup.
  input = {
    region             = local.region
    account_id         = data.aws_caller_identity.current.account_id
    module_instance_id = var.module_instance_id == null ? "" : var.module_instance_id
    script             = file("${path.module}/cleanup_build_resources.sh")
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = self.input.script

    environment = {
      AWS_REGION         = self.input.region
      AWS_ACCOUNT_ID     = self.input.account_id
      MODULE_INSTANCE_ID = self.input.module_instance_id
    }
  }
}
