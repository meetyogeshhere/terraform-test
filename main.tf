terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Create new ECR Repository
resource "aws_ecr_repository" "site_repo" {
  name                 = "treehouse-site-2025"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# Use existing default VPC
data "aws_vpc" "main" {
  default = true
}

# Use existing public subnets in default VPC
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

# Get subnet IDs for two availability zones
data "aws_subnet" "public_a" {
  id = element(data.aws_subnets.public.ids, 0)
}

data "aws_subnet" "public_b" {
  id = element(data.aws_subnets.public.ids, 1)
}

# Security Group
resource "aws_security_group" "web" {
  vpc_id = data.aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Treehouse2025WebSG"
  }
}

# Load Balancer
resource "aws_lb" "main" {
  name               = "Treehouse2025ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = [data.aws_subnet.public_a.id, data.aws_subnet.public_b.id]
  tags = {
    Name = "Treehouse2025ALB"
  }
}

# Target Group with Health Check
resource "aws_lb_target_group" "main" {
  name        = "Treehouse2025TG"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
  target_type = "ip"  # For awsvpc compatibility
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = {
    Name = "Treehouse2025TG"
  }
}

# Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "Treehouse2025Cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "Treehouse2025ECSTaskRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = "Treehouse2025Task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([
    {
      name  = "treehouse2025-container"
      image = "${aws_ecr_repository.site_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
      healthCheck = {
        command = ["CMD-SHELL", "curl -f http://localhost/ || exit 1"]
        interval = 30
        timeout = 5
        retries = 3
        startPeriod = 10
      }
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "main" {
  name            = "Treehouse2025Service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    security_groups  = [aws_security_group.web.id]
    subnets          = [data.aws_subnet.public_a.id, data.aws_subnet.public_b.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "treehouse2025-container"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.main]
}