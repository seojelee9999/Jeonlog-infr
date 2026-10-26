# ── 기존 인프라 참조 (생성하지 않음) ────────────────────────────

data "aws_s3_bucket" "app" {
  bucket = var.s3_bucket_name
}

data "aws_caller_identity" "current" {}

data "aws_acm_certificate" "this" {
  domain   = var.acm_certificate_domain
  statuses = ["ISSUED"]
}
