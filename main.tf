terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"  # Your playground area
}

# Toy chest for Docker images (ECR Repository)
resource "aws_ecr_repository" "my_site_repo" {
  name                 = "my-treehouse-site"
  image_tag_mutability = "MUTABLE"  # Let us update tags

  image_scanning_configuration {
    scan_on_push = true  # Check for bugs automatically
  }
}

# VPC (safe neighborhood for your site)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "TreehouseVPC"
  }
}

# Public subnets (streets where visitors can reach you)
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
  availability_zone = "us-east-1a"
  tags = {
    Name = "PublicSubnetB"
  }
}

# Internet gateway (door to the outside world)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "TreehouseIGW"
  }
}

# Route table (map to the internet)
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

# Security group (fence: allow web traffic)
resource "aws_security_group" "web" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Anyone can visit port 80
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

# Load balancer (welcomer for visitors)
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

# Target group (where to send visitors)
resource "aws_lb_target_group" "main" {
  name     = "TreehouseTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "TreehouseTargetGroup"
  }
}

# Listener (ear on the door for port 80)
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn  # Fixed: Use aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.id
  }
}

# ECS Cluster (playground for your Docker boxes)
resource "aws_ecs_cluster" "main" {
  name = "TreehouseCluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Task definition (what your Docker box does)
resource "aws_ecs_task_definition" "main" {
  family                   = "TreehouseTask"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"  # Small brain for the box
  memory                   = "512"  # Small memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn  # Magic to pull from ECR

  container_definitions = jsonencode([
    {
      name  = "treehouse-container"
      image = "${aws_ecr_repository.my_site_repo.repository_url}:latest"  # Your Docker box from ECR
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

# IAM role for ECS to pull Docker images
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

# ECS Service (keeps your box running)
resource "aws_ecs_service" "main" {
  name            = "TreehouseService"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1  # One box running
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