data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-vpc"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each                = { for idx, cidr in var.public_cidrs : tostring(idx) => cidr }
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = local.azs[tonumber(each.key)]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-public-${each.key}",
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each          = { for idx, cidr in var.private_cidrs : tostring(idx) => cidr }
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = local.azs[tonumber(each.key)]

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-private-${each.key}",
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-nat-eip"
  })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["0"].id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-nat"
  })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  route_table_id = aws_route_table.private.id
  subnet_id      = each.value.id
}

resource "aws_security_group" "vpce" {
  name        = "${var.project}-${var.env}-vpce-sg"
  description = "Allow VPC to Interface Endpoints (443)"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-vpce-sg"
  })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${var.region}.s3"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-vpce-s3"
  })
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.logs"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-vpce-logs"
  })
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.env}-alb-sg"
  description = "Allow HTTP from the Internet"
  vpc_id      = aws_vpc.main.id

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

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-alb-sg"
  })
}

resource "aws_lb" "app" {
  name               = "${var.project}-${var.env}-alb"
  load_balancer_type = "application"
  subnets            = [for s in aws_subnet.public : s.id]
  security_groups    = [aws_security_group.alb.id]
  idle_timeout       = 60

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-alb"
  })
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project}-${var.env}-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_ecr_repository" "app" {
  name = var.ecr_repo_name

  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.project}-ecr"
    Environment = var.env
  }
}

resource "aws_ecs_cluster" "this" {
  name = "${var.project}-${var.env}-cluster"
  tags = var.tags
}

resource "aws_iam_role" "task_execution" {
  name = "${var.project}-${var.env}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "exec_attach" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${var.project}-${var.env}-ecs-task"
  assume_role_policy = aws_iam_role.task_execution.assume_role_policy
  tags               = var.tags
}

resource "aws_security_group" "svc" {
  name        = "${var.project}-${var.env}-svc-sg"
  description = "Allow HTTP from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-svc-sg"
  })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}-${var.env}"
  retention_in_days = 3
  tags              = var.tags
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-${var.env}"
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = "app"
      image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repo_name}:${var.image_tag}"
      portMappings = [{
        containerPort = "${var.container_port}"
        hostPort      = "${var.container_port}"
        protocol      = "tcp"
      }]
      essential = true
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "${aws_cloudwatch_log_group.app.name}"
          awslogs-region        = "${var.region}"
          awslogs-stream-prefix = "app"
        }
      }

      environment = [
        { name = "DB_HOST", value = "${aws_db_instance.app.address}"},
        { name = "DB_PORT", value = "${tostring(var.db_port)}"},
        { name = "DB_USER", value = "${var.db_username}"},
        { name = "DB_PASSWORD", value = "${var.db_password}"},
        { name = "DB_NAME", value = "${var.db_name}"}
      ]
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  tags = var.tags
}

resource "aws_ecs_service" "app" {
  name                   = "${var.project}-${var.env}-svc"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.app.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = false

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.svc.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
  tags       = var.tags
}

resource "aws_db_subnet_group" "app" {
  name = "${var.project}-${var.env}-dbsubnet"
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-dbsubnet"
  })
}

resource "aws_security_group" "db" {
  name = "${var.project}-${var.env}-db.sg"
  vpc_id = aws_vpc.main.id

  ingress {
    protocol = "tcp"
    from_port = var.db_port
    to_port = var.db_port
    security_groups = [aws_security_group.svc.id]
  }

  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-db-sg"
  })
}

resource "aws_db_instance" "app" {
  identifier = "${var.project}-${var.env}"
  engine = var.db_engine
  engine_version = var.db_engine_version
  instance_class = "db.t4g.micro"
  allocated_storage = 20
  max_allocated_storage = 0
  storage_type = "gp3"
  username = var.db_username
  password = var.db_password
  db_name = var.db_name
  port = var.db_port

  db_subnet_group_name = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible = false
  multi_az = false

  skip_final_snapshot = true
  deletion_protection = false
  backup_retention_period = 0
  apply_immediately = true

  tags = var.tags
}

resource "aws_cloudfront_distribution" "alb_front" {
  depends_on = [ aws_lb.app ]
  enabled = true
  comment = "${var.project}-${var.env} via ALB"
  price_class = "PriceClass_100"

  origin {
    domain_name = aws_lb.app.dns_name
    origin_id = "alb-origin"

    custom_origin_config {
      origin_protocol_policy = "http-only"
      http_port = 80
      https_port = 443
      origin_ssl_protocols = [ "TLSv1.2" ]
    }
  }

  default_cache_behavior {
    target_origin_id = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [ "GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE" ]
    cached_methods = [ "GET", "HEAD" ]
    compress = true

    min_ttl = 0
    default_ttl = 0
    max_ttl = 0

    forwarded_values {
      query_string = true
      headers = [ "*" ]
      cookies {
        forward = "all"
      }
    }
  }
    restrictions {
      geo_restriction { restriction_type = "none"}
    }

    viewer_certificate {
      cloudfront_default_certificate = true
    }

    is_ipv6_enabled = true
  
    //logging_config {
    //  bucket = "your-log-bucket.s3.amazonaws.com"
    //  prefix = "cloudfront/"
    //  include_cookies = true
    //}
}