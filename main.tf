locals { name = "${var.project}-${var.env}" }
data "aws_availability_zones" "available" { state = "available" }

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(var.tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.this.id }

resource "aws_subnet" "public" {
  for_each = { for i, cidr in var.public_cidrs : i => { cidr = cidr, az = data.aws_availability_zones.available.names[i] } }
  vpc_id = aws_vpc.this.id
  cidr_block = each.value.cidr
  availability_zone = each.value.az
  map_public_ip_on_launch = true
  tags = merge(var.tags, { Name = "${local.name}-public-${each.value.az}" })
}

resource "aws_subnet" "private" {
  for_each = { for i, cidr in var.private_cidrs : i => { cidr = cidr, az = data.aws_availability_zones.available.names[i] } }
  vpc_id = aws_vpc.this.id
  cidr_block = each.value.cidr
  availability_zone = each.value.az
  tags = merge(var.tags, { Name = "${local.name}-private-${each.value.az}" })
}

resource "aws_eip" "nat" { vpc = true }
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" { vpc_id = aws_vpc.this.id }
resource "aws_route" "public_inet" {
  route_table_id = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
}
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public
  route_table_id = aws_route_table.public.id
  subnet_id = each.value.id
}

resource "aws_route_table" "private" { vpc_id = aws_vpc.this.id }
resource "aws_route" "private_nat" {
  route_table_id = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.nat.id
}
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private
  route_table_id = aws_route_table.private.id
  subnet_id = each.value.id
}

# VPCEs (S3 gateway + CloudWatch interface) to reduce NAT traffic
resource "aws_security_group" "vpce" {
  name   = "${local.name}-vpce-sg"
  vpc_id = aws_vpc.this.id
  ingress { from_port = 443 to_port = 443 protocol = "tcp" cidr_blocks = [var.vpc_cidr] }
  egress  { from_port = 0   to_port = 0   protocol = "-1"  cidr_blocks = ["0.0.0.0/0"] }
}
resource "aws_vpc_endpoint" "s3" {
  vpc_id = aws_vpc.this.id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [aws_route_table.private.id]
}
resource "aws_vpc_endpoint" "logs" {
  vpc_id = aws_vpc.this.id
  service_name = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type = "Interface"
  subnet_ids = [for s in aws_subnet.private : s.id]
  security_group_ids = [aws_security_group.vpce.id]
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "monitoring" {
  vpc_id = aws_vpc.this.id
  service_name = "com.amazonaws.${var.region}.monitoring"
  vpc_endpoint_type = "Interface"
  subnet_ids = [for s in aws_subnet.private : s.id]
  security_group_ids = [aws_security_group.vpce.id]
  private_dns_enabled = true
}

# ECR
resource "aws_ecr_repository" "app" {
  name = var.ecr_repo_name
  image_scanning_configuration { scan_on_push = true }
}

# ALB
resource "aws_security_group" "alb" {
  name   = "${local.name}-alb-sg"
  vpc_id = aws_vpc.this.id
  ingress { from_port = 80 to_port = 80 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
}
resource "aws_lb" "app_alb" {
  name = "${local.name}-alb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb.id]
  subnets = [for s in aws_subnet.public : s.id]
}
resource "aws_lb_target_group" "app_tg" {
  name = "${local.name}-tg"
  port = var.container_port
  protocol = "HTTP"
  target_type = "ip"
  vpc_id = aws_vpc.this.id
  health_check { path="/healthz" port=var.container_port interval=10 timeout=5 healthy_threshold=3 unhealthy_threshold=3 matcher="200" }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port = 80
  protocol = "HTTP"
  default_action { type="forward" target_group_arn = aws_lb_target_group.app_tg.arn }
}

# ECS
resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"
  setting { name="containerInsights" value="enabled" }
}
resource "aws_iam_role" "task_exec" {
  name = "${local.name}-task-exec-role"
  assume_role_policy = jsonencode({
    Version="2012-10-17",
    Statement=[{ Action="sts:AssumeRole", Effect="Allow", Principal={ Service="ecs-tasks.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "task_exec_attach" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_cloudwatch_log_group" "app" { name="/ecs/${local.name}" retention_in_days=3 }

resource "aws_ecs_task_definition" "app" {
  family = "${local.name}-task"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu    = var.cpu
  memory = var.memory
  execution_role_arn = aws_iam_role.task_exec.arn
  container_definitions = jsonencode([{
    name="app",
    image="${aws_ecr_repository.app.repository_url}:${var.image_tag}",
    essential=true,
    portMappings=[{ containerPort=var.container_port, protocol="tcp" }],
    logConfiguration={ logDriver="awslogs", options={
      awslogs-group=aws_cloudwatch_log_group.app.name,
      awslogs-region=var.region,
      awslogs-stream-prefix="ecs"
    }}
  }])
  runtime_platform { operating_system_family="LINUX" cpu_architecture="X86_64" }
}

resource "aws_security_group" "ecs_service" {
  name = "${local.name}-svc-sg"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port = var.container_port
    to_port   = var.container_port
    protocol  = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress { from_port=0 to_port=0 protocol="-1" cidr_blocks=["0.0.0.0/0"] }
}

resource "aws_ecs_service" "app" {
  name            = "${local.name}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  platform_version = "1.4.0"
  network_configuration {
    subnets         = [for s in aws_subnet.private : s.id]
    security_groups = [aws_security_group.ecs_service.id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "app"
    container_port   = var.container_port
  }
  depends_on = [aws_lb_listener.http]
}
