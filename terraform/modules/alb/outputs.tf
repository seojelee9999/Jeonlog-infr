output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "ALB DNS 주소 (앱 접근 URL)"
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "target_group_arn" {
  value       = aws_lb_target_group.this.arn
  description = "ASG가 등록될 Target Group ARN"
}
