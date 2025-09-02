variable "project" {
  type    = string
  default = "my-platform"
}
variable "env" {
  type    = string
  default = "dev"
}
variable "nat_strategy" {
  description = "single(테스트환경)/per_az(운영환경), 빈 문자열은 single 취급"
  type        = string
  default     = ""
  validation {
    condition     = var.nat_strategy == "" || contains(["single", "per_az"], var.nat_strategy)
    error_message = "nat_strategy must be empty, 'single' or 'per_az'."
  }
}
variable "region" {
  type    = string
  default = "ap-northeast-2"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "public_cidrs" {
  type = list(string)
  default = ["10.0.0.0/24",
    "10.0.1.0/24",
  "10.0.2.0/24"]
}
variable "private_cidrs" {
  type = list(string)
  default = ["10.0.10.0/24",
    "10.0.11.0/24",
  "10.0.12.0/24"]
}

variable "desired_count" {
  type    = number
  default = 2
}
variable "cpu" {
  type    = number
  default = 256
}
variable "memory" {
  type    = number
  default = 512
}
variable "container_port" {
  type    = number
  default = 8080
}
variable "ecr_repo_name" {
  description = "ECR repository name"
  type        = string
  default     = "my-sample-api"
}
variable "image_tag" {
  type    = string
  default = "latest"
}

variable "tags" {
  type    = map(string)
  default = { owner = "candidate", cost-center = "portfolio", app = "ha-platform" }
}

variable "db_engine" {
  type    = string
  default = "mysql"
}

variable "db_engine_version" {
  type    = string
  default = "8.0.42"
}

variable "db_name" {
  type    = string
  default = "appda"
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_port" {
  type    = number
  default = 3306
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "enable_multi_az" {
  type    = bool
  default = false
}

variable "enable_pi" {
  type    = bool
  default = false
}

variable "pi_retention_days" {
  type    = number
  default = 7
}

variable "enable_enhanced_monitoring" {
  type    = bool
  default = false
}

variable "monitoring_interval" {
  type    = number
  default = 60
}

variable "export_slow_logs" {
  type    = bool
  default = false
}

variable "db_parameter_family" {
  type    = string
  default = "mysql8.0"
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "skip_final_snapshot" {
  type    = bool
  default = true
}
//variable "domain_name" {
//  type = string
//}

//variable "subdomain" {
//  type = string
//  default = "app"
//}

variable "alert_email" {
  description = "비용/이상징후 알림 이메일"
  type        = string
}

variable "rds_cpu_high_threshold" {
  type    = number
  default = 80
}

variable "rds_free_storage_gb" {
  type    = number
  default = 2
}

variable "ecs_tasks_missing_periods" {
  type    = number
  default = 2
}

variable "yourls_admin_pass" {
  description = "YOURLS admin password"
  type        = string
  sensitive   = true
}

variable "app_blue_weight" {
  type        = number
  default     = 100
  description = "ALB weight for app blue target group"
}

variable "app_green_weight" {
  type        = number
  default     = 0
  description = "ALB weight for app green target group"
}