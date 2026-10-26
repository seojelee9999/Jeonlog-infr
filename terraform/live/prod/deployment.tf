# 이미지 URL (GitHub Actions가 배포 시 업데이트 → Instance Refresh로 새 인스턴스에 적용)
resource "aws_ssm_parameter" "ecr_image_url" {
  name  = "/jeonlog/prod/ecr-image-url"
  type  = "String"
  value = var.ecr_image_url != null ? var.ecr_image_url : "PLACEHOLDER"

  lifecycle {
    ignore_changes = [value]
  }
}
