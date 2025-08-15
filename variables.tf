variable "project" {
  type    = string
  default = "my-platform"
}
variable "env" {
  type    = string
  default = "dev"
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
