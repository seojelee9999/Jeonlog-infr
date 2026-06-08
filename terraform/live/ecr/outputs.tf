output "repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "ECR 레포 URL (dev/prod terraform.tfvars의 ecr_image_url에 사용)"
}

output "registry_url" {
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.id}.amazonaws.com"
  description = "ECR 로그인 시 사용할 레지스트리 URL"
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "GitHub Actions workflow의 role-to-assume 값"
}
