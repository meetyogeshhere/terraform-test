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
  name = "my-treehouse-site"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "TreehouseVPC"
  }
}

# Public Subnets
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "PublicSubnetA"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"  # Fixed
  tags = {
    Name = "PublicSubnetB"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "TreehouseIGW"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "web" {
  vpc_id = aws_vpc.main.id
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
    Name = "WebSecurityGroup"
  }
}

# Load Balancer
resource "aws_lb" "main" {
  name               = "TreehouseALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  tags = {
    Name = "TreehouseALB"
  }
}

# Target Group with Health Check
resource "aws_lb_target_group" "main" {
  name     = "TreehouseTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
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
    Name = "TreehouseTargetGroup"
  }
}

# Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.id
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "TreehouseCluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = "TreehouseTask"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([
    {
      name  = "treehouse-container"
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

# IAM Role for ECS
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "TreehouseECSTaskExecutionRole"
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

# ECS Service
resource "aws_ecs_service" "main" {
  name            = "TreehouseService"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    security_groups  = [aws_security_group.web.id]
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.main.id
    container_name   = "treehouse-container"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.main]
}