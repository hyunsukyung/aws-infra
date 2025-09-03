data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs        = slice(data.aws_availability_zones.available.names, 0, 3)
  nat_per_az = var.nat_strategy == "per_az"
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
  for_each = local.nat_per_az ? aws_subnet.public : { "0" = aws_subnet.public["0"] }
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-nat-eip-${each.key}"
  })
}

resource "aws_nat_gateway" "nat" {
  for_each      = aws_eip.nat
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-nat-${each.key}"
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

resource "aws_route_table" "private_single" {
  count  = local.nat_per_az ? 0 : 1
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = values(aws_nat_gateway.nat)[0].id
  }
  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-private-rt"
  })
}

resource "aws_route_table_association" "private_single" {
  for_each       = local.nat_per_az ? {} : aws_subnet.private
  route_table_id = aws_route_table.private_single[0].id
  subnet_id      = each.value.id
}

resource "aws_route_table" "private_per_az" {
  for_each = local.nat_per_az ? aws_subnet.private : {}
  vpc_id   = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[each.key].id
  }
  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-private-rt-${each.key}"
  })
}

resource "aws_route_table_association" "private_per_az" {
  for_each       = local.nat_per_az ? aws_subnet.private : {}
  route_table_id = aws_route_table.private_per_az[each.key].id
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

locals {
  private_rt_ids_single = local.nat_per_az ? [] : [aws_route_table.private_single[0].id]
  private_rt_ids_per_az = local.nat_per_az ? [for rt in values(aws_route_table.private_per_az) : rt.id] : []
  private_rt_ids        = concat(local.private_rt_ids_single, local.private_rt_ids_per_az)
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${var.region}.s3"
  route_table_ids   = local.private_rt_ids

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
  name                 = "${var.project}-${var.env}-tg"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

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

resource "aws_lb_target_group" "api" {
  name                 = "${var.project}-${var.env}-tg-api"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-tg-api"
  })
}

resource "aws_lb_target_group" "admin" {
  name                 = "${var.project}-${var.env}-tg-admin"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-tg-admin"
  })
}


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.app.arn
        weight = var.app_blue_weight
      }
      target_group {
        arn    = aws_lb_target_group.app_green.arn
        weight = var.app_green_weight
      }
      stickiness {
        enabled  = false
        duration = 1
      }
    }
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "admin" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.admin.arn
  }

  condition {
    path_pattern {
      values = ["/admin/*"]
    }
  }
}

resource "aws_ecr_repository" "app" {
  name = var.ecr_repo_name

  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  force_delete = true
  tags = {
    Name        = "${var.project}-ecr"
    Environment = var.env
  }
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

      environment = concat([
        { name = "PORT", value = tostring(var.container_port) },
        { name = "DB_HOST", value = "${aws_db_instance.app.address}" },
        { name = "DB_PORT", value = "${tostring(var.db_port)}" },
        { name = "DB_NAME", value = "${var.db_name}" },

        { name = "YOURLS_SITE", value = "http://${aws_lb.app.dns_name}" },
        { name = "YOURLS_USER", value = "admin" },
        { name = "YOURLS_PASS", value = var.yourls_admin_pass }
      ], [])

      secrets = concat([
        { name = "DB_USER", valueFrom = "${aws_secretsmanager_secret.db.arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.db.arn}:password::" }
      ], [])
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
  enable_execute_command = false

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

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

resource "aws_ecs_service" "app_green" {
  name            = "${var.project}-${var.env}-svc-app-green"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 0

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.svc.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_green.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  tags = var.tags
}

resource "aws_ecs_cluster" "this" {
  name = "${var.project}-${var.env}-cluster"
  tags = var.tags

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }
}

resource "aws_ecs_service" "api" {
  name            = "${var.project}-${var.env}-svc-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.svc.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
  tags       = var.tags
}

resource "aws_ecs_service" "admin" {
  name            = "${var.project}-${var.env}-svc-admin"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.svc.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.admin.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
  tags       = var.tags
}

resource "aws_db_subnet_group" "app" {
  name       = "${var.project}-${var.env}-dbsubnet"
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-dbsubnet"
  })
}

resource "aws_security_group" "db" {
  name   = "${var.project}-${var.env}-db.sg"
  vpc_id = aws_vpc.main.id

  ingress {
    protocol        = "tcp"
    from_port       = var.db_port
    to_port         = var.db_port
    security_groups = [aws_security_group.svc.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-db-sg"
  })
}

resource "aws_db_instance" "app" {
  identifier     = "${var.project}-${var.env}"
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 0
  storage_type          = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  multi_az                = var.enable_multi_az
  backup_retention_period = var.backup_retention_days
  copy_tags_to_snapshot   = true

  maintenance_window         = "sun:19:00-sun:19:30"
  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot

  parameter_group_name = aws_db_parameter_group.app.name

  enabled_cloudwatch_logs_exports = var.export_slow_logs ? ["error", "slowquery"] : []

  performance_insights_enabled          = var.enable_pi
  performance_insights_retention_period = var.enable_pi ? var.pi_retention_days : null

  monitoring_interval = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? aws_iam_role.rds_em[0].arn : null

  username = var.db_username
  password = var.db_password
  db_name  = var.db_name
  port     = var.db_port

  apply_immediately = true
  tags              = var.tags
}

resource "aws_iam_role_policy" "exec_secrets" {
  name = "${var.project}-${var.env}-ecs-exec-secrets"
  role = aws_iam_role.task_execution.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = ["secretsmanager:GetSecretValue"],
        Resource = [
          aws_secretsmanager_secret.db.arn
        ]
      }
    ]
  })
}

resource "aws_secretsmanager_secret" "db" {
  name = "${var.project}-${var.env}-db"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}

resource "aws_s3_bucket_ownership_controls" "static" {
  bucket = aws_s3_bucket.static.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "static" {
  depends_on = [aws_s3_bucket_ownership_controls.static]
  bucket     = aws_s3_bucket.static.id
  acl        = "private"
}

resource "aws_s3_bucket" "static" {
  bucket = "${var.project}-${var.env}-static"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-static"
  })
}

resource "aws_cloudfront_origin_access_identity" "static" {
  comment = "OAI for static S3"
}

resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow",
      Principal = {
        CanonicalUser = aws_cloudfront_origin_access_identity.static.s3_canonical_user_id
      },
      Action   = "s3:GetObject",
      Resource = "${aws_s3_bucket.static.arn}/*"
    }]
  })
}

resource "aws_cloudfront_distribution" "alb_front" {
  depends_on  = [aws_lb.app]
  enabled     = true
  comment     = "${var.project}-${var.env} via ALB"
  price_class = "PriceClass_100"

  origin {
    domain_name = aws_lb.app.dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      origin_protocol_policy = "http-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id   = "s3-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.static.cloudfront_access_identity_path
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
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

/*
resource "aws_wafv2_web_acl" "cf" {
  provider = aws.us_east_1
  name     = "${var.project}-${var.env}-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-${var.env}-waf"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1
    statement {
      managed_rule_group_statement {
        name        = "AWS-AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    override_action {
      count {}
      //none{} 
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }
}

resource "aws_wafv2_web_acl_association" "cf_assoc" {
  provider     = aws.us_east_1
  resource_arn = aws_cloudfront_distribution.alb_front.arn
  web_acl_arn  = aws_wafv2_web_acl.cf.arn
}
*/

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu50" {
  name               = "${var.project}-${var.env}-cpu50"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "mem65" {
  name               = "${var.project}-${var.env}-mem65"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 65
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

locals {
  alb_reqcount_label = "${aws_lb.app.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
}

resource "aws_appautoscaling_policy" "req_per_target" {
  name               = "${var.project}-${var.env}-req-per-target"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 100
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = local.alb_reqcount_label
    }
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

resource "aws_sns_topic" "alerts" { name = "${var.project}-${var.env}-alerts" }

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project}-${var.env}-alb-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.app.arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu80" {
  alarm_name  = "${var.project}-${var.env}-ecs-cpu80"
  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.app.name
  }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_db_parameter_group" "app" {
  name        = "${var.project}-${var.env}-mysql"
  family      = var.db_parameter_family
  description = "Minimal MySQL params for ${var.project}-${var.env}"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = var.tags
  //필요해지면 추후 slow_query_log, long_query_time, performance_schemer 등을 여기에 추가해서 튜닝하면됨.
}

data "aws_iam_policy_document" "rds_em_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_em" {
  count              = var.enable_enhanced_monitoring ? 1 : 0
  name               = "${var.project}-${var.env}-rds-em"
  assume_role_policy = data.aws_iam_policy_document.rds_em_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_em_attach" {
  count      = var.enable_enhanced_monitoring ? 1 : 0
  role       = aws_iam_role.rds_em[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_lb_target_group" "app_green" {
  name        = "${var.project}-${var.env}-tg-green"
  port        = var.container_port
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
    Name = "${var.project}-${var.env}-tg-green"
  })
}

resource "aws_lb_target_group" "api_green" {
  name        = "${var.project}-${var.env}-tg-api-green"
  port        = var.container_port
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
    Name = "${var.project}-${var.env}-tg-api-green"
  })
}

resource "aws_lb_target_group" "admin_green" {
  name        = "${var.project}-${var.env}-tg-admin-green"
  port        = var.container_port
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
    Name = "${var.project}-${var.env}-tg-admin-green"
  })
}

data "aws_iam_policy_document" "codedeploy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "tg_unhealthy" {
  alarm_name          = "${var.project}-${var.env}-tg-unhealthy"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_task_missing" {
  alarm_name          = "${var.project}-${var.env}-ecs-tasks-missing}"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = var.ecs_tasks_missing_periods
  treat_missing_data  = "breaching"

  metric_query {
    id = "desired"
    metric {
      namespace   = "AWS/ECS"
      metric_name = "DesiredTaskCount"
      dimensions = {
        ClusterName = aws_ecs_cluster.this.name
        ServiceName = aws_ecs_service.app.name
      }
      period = 60
      stat   = "Average"
    }
  }

  metric_query {
    id = "running"
    metric {
      namespace   = "AWS/ECS"
      metric_name = "RunningTaskCount"
      dimensions = {
        ClusterName = aws_ecs_cluster.this.name
        ServiceName = aws_ecs_service.app.name
      }
      period = 60
      stat   = "Average"
    }
  }

  metric_query {
    id          = "diff"
    expression  = "desired - running"
    label       = "Tasks short"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.project}-${var.env}-rds-cpu-high"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.rds_cpu_high_threshold
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.app.id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

locals {
  rds_free_storage_bytes = var.rds_free_storage_gb * 1024 * 1024 * 1024
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  alarm_name          = "${var.project}-${var.env}-rds-freestorage-low"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = local.rds_free_storage_bytes
  comparison_operator = "LessThanThreshold"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.app.id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules : [
      {
        rulePriority : 1,
        description : "Expire untagged images after 7 days",
        selection : {
          tagStatus : "untagged",
          countType : "sinceImagePushed",
          countUnit : "days",
          countNumber : 7
        },
        action : { type : "expire" }
      },
      {
        rulePriority : 10,
        description : "Keep last 50 images",
        selection : {
          tagStatus : "any",
          countType : "imageCountMoreThan",
          countNumber : 50
        },
        action : { type : "expire" }
      }
    ]
  })
}

resource "aws_budgets_budget" "monthly_cost" {
  name         = "${var.project}-${var.env}-monthly"
  budget_type  = "COST"
  limit_amount = "20"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
/*
resource "aws_ce_anomaly_monitor" "service" {
  name              = "${var.project}-${var.env}-anomaly-service"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "Service" {
  name             = "${var.project}-${var.env}-anomaly-sub"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.service.arn]
  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }
}
*/