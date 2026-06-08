variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "vpc_name" {
  type        = string
  description = "VPC name tag"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names (e.g. jeonlog-prod)"
}

variable "azs" {
  type        = list(string)
  description = "List of availability zones (e.g. [ap-northeast-2a, ap-northeast-2b])"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets (ALB + ASG nodes), one per AZ"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets (RDS only), one per AZ"
}

variable "app_port" {
  type        = number
  description = "Port that the Spring application listens on"
  default     = 8080
}

variable "ssh_ingress_cidrs" {
  type        = list(string)
  description = "SSH 허용 IP 목록 (빈 리스트면 SSH 룰 미생성)"
  default     = []
}
