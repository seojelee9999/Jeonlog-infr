output "alb_dns_name" {
  value       = module.alb.alb_dns_name
  description = "앱 접근 URL: http://<alb_dns_name>"
}

output "asg_name" {
  value = module.asg.asg_name
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "RDS 마이그레이션 시 사용할 프라이빗 서브넷"
  value       = module.network.private_subnet_ids
}

output "rds_subnet_group_name" {
  description = "RDS 스냅샷 복원 시 지정할 subnet group 이름"
  value       = module.network.rds_subnet_group_name
}

output "rds_security_group_id" {
  description = "RDS 스냅샷 복원 시 지정할 보안그룹 ID"
  value       = module.network.rds_security_group_id
}

output "s3_bucket_name" {
  value = data.aws_s3_bucket.app.bucket
}

output "rds_endpoint" {
  description = "앱 DB 연결 주소 (포트 제외)"
  value       = aws_db_instance.jeonlog.address
}

output "grafana_url" {
  description = "Grafana 대시보드 URL (2차 TFA 후 확인)"
  value       = "http://${aws_instance.grafana.public_ip}:3000"
}
