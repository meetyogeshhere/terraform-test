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

# Use existing ECR Repository
data "aws_ecr_repository" "my_site_repo" {
  name = "new-treehouse-site-2025"
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
    Name = "NewWebSecurityGroup"
  }
}

# Use existing Load Balancer
data "aws_lb" "main" {
  name = "NewTreehouseALB"
}

# Use existing Target Group
data "aws_lb_target_group" "main" {
  name = "NewTreehouseTargetGroup"
}

# Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = data.aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = data.aws_lb_target_group.main.arn
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "NewTreehouseCluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = "NewTreehouseTask"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([
    {
      name  = "new-treehouse-container"
      image = "${data.aws_ecr_repository.my_site_repo.repository_url}:latest"
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

# Use existing IAM Role
data "aws_iam_role" "ecs_task_execution_role" {
  name = "NewTreehouseECSTaskExecutionRole"
}

# ECS Service
resource "aws_ecs_service" "main" {
  name            = "NewTreehouseService"
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
    target_group_arn = data.aws_lb_target_group.main.arn
    container_name   = "new-treehouse-container"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.main]
}