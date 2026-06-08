output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB + ASG nodes)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (RDS)"
  value       = aws_subnet.private[*].id
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "App (Spring) security group ID"
  value       = aws_security_group.app.id
}

output "rds_security_group_id" {
  description = "RDS security group ID — 기존 RDS에 이 SG를 추가해야 함"
  value       = aws_security_group.rds.id
}

output "rds_subnet_group_name" {
  description = "RDS DB subnet group name"
  value       = aws_db_subnet_group.rds.name
}
