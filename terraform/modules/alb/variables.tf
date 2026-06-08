variable "name_prefix" {
  type        = string
  description = "모든 리소스 이름 앞에 붙는 prefix"
}

variable "vpc_id" {
  type        = string
  description = "ALB가 속할 VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "ALB를 배치할 서브넷 ID 목록 (2개 이상 AZ 권장)"
}

variable "security_group_id" {
  type        = string
  description = "ALB에 적용할 보안그룹 ID"
}

variable "app_port" {
  type        = number
  default     = 8080
  description = "애플리케이션 포트 (Target Group이 이 포트로 포워딩)"
}

variable "health_check_path" {
  type        = string
  default     = "/actuator/health"
  description = "ALB 헬스체크 경로"
}

variable "acm_certificate_arn" {
  type        = string
  description = "HTTPS 리스너에 적용할 ACM 인증서 ARN"
}

variable "alb_logs_bucket" {
  type        = string
  description = "ALB 액세스 로그를 저장할 S3 버킷 이름 (비어있으면 로그 비활성화)"
  default     = ""
}
