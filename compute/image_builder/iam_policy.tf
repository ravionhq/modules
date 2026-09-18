################################################################################
# Pipeline execution policy
#
# What a deploy pipeline needs to build an image without Terraform: start this
# pipeline, then follow the run to the image it produces. Attach it to the role
# of the step that runs the build.
################################################################################

resource "aws_iam_policy" "pipeline_execution" {
  count = var.create_pipeline_execution_policy ? 1 : 0

  name        = local.pipeline_execution_policy_name
  description = "Starts the ${var.name} Image Builder pipeline and reads the images it produces."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartAndReadThisPipeline"
        Effect = "Allow"
        Action = [
          "imagebuilder:StartImagePipelineExecution",
          "imagebuilder:GetImagePipeline",
          "imagebuilder:ListImagePipelineImages",
        ]
        Resource = aws_imagebuilder_image_pipeline.this.arn
      },
      {
        Sid      = "ReadTheImagesItProduces"
        Effect   = "Allow"
        Action   = "imagebuilder:GetImage"
        Resource = local.pipeline_image_arn
      },
    ]
  })

  tags = local.tags
}
