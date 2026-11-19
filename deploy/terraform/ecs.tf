resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days

  tags = { Name = "${local.name}-logs" }
}

resource "aws_iam_role" "task_execution" {
  name = "${local.name}-ecs-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = { Name = "${local.name}-ecs-exec" }
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_cluster" "app" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${local.name}-cluster" }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name = var.project_name
      # Référence docker_registry_image : garantit que l'image est poussée avant le service
      image     = docker_registry_image.app.name
      essential = true

      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]

      mountPoints = [{
        sourceVolume  = "efs-logs"
        containerPath = "/juice-shop/logs"
        readOnly      = false
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  volume {
    name = "efs-logs"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.app.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.app.id
      }
    }
  }

  tags = { Name = "${local.name}-task" }
}

resource "aws_ecs_service" "app" {
  name            = "${local.name}-service"
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 120

  # Le tag d'image reste "latest" : sans ceci, une nouvelle image poussée
  # ne serait pas déployée. Le digest change à chaque nouveau contenu.
  force_new_deployment = true
  triggers = {
    image_digest = docker_registry_image.app.sha256_digest
  }

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.project_name
    container_port   = var.container_port
  }

  depends_on = [
    aws_lb_listener.http,
    aws_lb_listener.https,
    aws_efs_mount_target.app,
    aws_vpc_endpoint.interface,
    aws_vpc_endpoint.s3,
  ]

  tags = { Name = "${local.name}-service" }
}
