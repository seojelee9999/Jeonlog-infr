variable "name_prefix" {
  type        = string
  description = "모든 리소스 이름 앞에 붙는 prefix"
}

variable "ami_id" {
  type        = string
  description = "Launch Template에 사용할 AMI ID"
}

variable "instance_type" {
  type        = string
  description = "EC2 인스턴스 타입"
}

variable "key_name" {
  type        = string
  description = "SSH 키페어 이름"
}

variable "instance_profile_name" {
  type        = string
  description = "EC2에 부여할 IAM Instance Profile 이름"
}

variable "security_group_id" {
  type        = string
  description = "ASG 인스턴스에 적용할 보안그룹 ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "ASG 인스턴스를 배치할 서브넷 ID 목록"
}

variable "target_group_arn" {
  type        = string
  description = "등록할 ALB Target Group ARN"
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 3
}

variable "desired_capacity" {
  type    = number
  default = 1
}

variable "user_data" {
  type        = string
  default     = ""
  description = "EC2 부팅 시 실행할 스크립트 (plain text, base64 인코딩은 모듈 내부에서 처리)"
}
