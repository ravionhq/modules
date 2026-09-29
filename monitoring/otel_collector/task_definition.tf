################################################################################
# Task Definition
################################################################################

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([{
    name                   = "collector"
    image                  = var.image
    essential              = true
    readonlyRootFilesystem = true

    # The AWS Distro for OpenTelemetry collector reads its whole configuration
    # from this variable, so a config change is a new task definition revision.
    environment = [{
      name  = "AOT_CONFIG_CONTENT"
      value = local.collector_config
    }]

    portMappings = [
      {
        name          = "otlp-grpc"
        containerPort = local.otlp_grpc_port
        protocol      = "tcp"
      },
      {
        name          = "otlp-http"
        containerPort = local.otlp_http_port
        protocol      = "tcp"
      },
    ]

    # /healthcheck queries the health_check extension on 127.0.0.1.
    healthCheck = {
      command     = ["CMD", "/healthcheck"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = local.region
        awslogs-stream-prefix = local.log_stream_prefix
      }
    }
  }])

  tags = local.tags
}
