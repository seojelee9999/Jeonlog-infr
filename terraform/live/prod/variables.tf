variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "name_prefix" {
  type        = string
  description = "모든 리소스 이름 앞에 붙는 prefix"
}

# ── VPC ───────────────────────────────────────────────────────

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type        = list(string)
  description = "사용할 AZ 목록"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "ALB + ASG용 퍼블릭 서브넷 CIDR (AZ 순서와 일치)"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "RDS용 프라이빗 서브넷 CIDR (AZ 순서와 일치)"
}

# ── 기존 리소스 참조 ──────────────────────────────────────────

variable "acm_certificate_domain" {
  type        = string
  description = "HTTPS에 사용할 ACM 인증서 도메인"
}

variable "db_identifier" {
  type        = string
  description = "기존 RDS 인스턴스 식별자 (마이그레이션 전까지 참조용)"
}

variable "s3_bucket_name" {
  type        = string
  description = "기존 S3 버킷 이름"
}

# ── 보안그룹 ──────────────────────────────────────────────────

variable "ssh_ingress_cidrs" {
  type        = list(string)
  description = "SSH 허용 IP 목록 (Ansible 실행 머신 IP)"
  default     = []
}

# ── 앱 설정 ───────────────────────────────────────────────────

variable "app_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/actuator/health"
}

# ── EC2 / ASG ─────────────────────────────────────────────────

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_name" {
  type = string
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

# ── RDS ───────────────────────────────────────────────────────

variable "db_snapshot_identifier" {
  type        = string
  description = "복원할 RDS 스냅샷 식별자"
}

variable "db_instance_class" {
  type        = string
  description = "RDS 인스턴스 타입"
  default     = "db.t3.small"
}

variable "db_password" {
  type        = string
  description = "RDS master 비밀번호 (스냅샷 복원 시 재설정)"
  sensitive   = true
}

# ── ECR ───────────────────────────────────────────────────────

variable "ecr_repository_arn" {
  type = string
}

variable "ecr_image_url" {
  type        = string
  description = "실행할 이미지 URL (예: 488675216847.dkr.ecr.ap-northeast-2.amazonaws.com/jeonlog-app:prod-abc123)"
  default     = null
}

# ── Grafana ───────────────────────────────────────────────────

variable "grafana_allowed_cidrs" {
  type        = list(string)
  description = "Grafana/Prometheus UI 접근 허용 CIDR 목록"
  default     = ["0.0.0.0/0"]
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana 관리자 비밀번호"
  sensitive   = true
}

# ── Redis ─────────────────────────────────────────────────────

variable "redis_password" {
  type        = string
  description = "Redis AUTH 비밀번호 (Grafana EC2에 공존)"
  sensitive   = true
}
