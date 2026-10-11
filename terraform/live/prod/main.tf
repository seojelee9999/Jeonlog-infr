# ── 기존 인프라 참조 (생성하지 않음) ────────────────────────────

data "aws_s3_bucket" "app" {
  bucket = var.s3_bucket_name
}

data "aws_caller_identity" "current" {}

# ── ALB 액세스 로그 전용 S3 버킷 ──────────────────────────────

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.name_prefix}-alb-logs"
  force_destroy = true

  tags = {
    Name = "${var.name_prefix}-alb-logs"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}

# ap-northeast-2 ELB 서비스 계정 ID: 600734575887
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket     = aws_s3_bucket.alb_logs.id
  depends_on = [aws_s3_bucket.alb_logs]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::600734575887:root" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/alb-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/alb-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.alb_logs.arn
      }
    ]
  })
}

data "aws_acm_certificate" "this" {
  domain   = var.acm_certificate_domain
  statuses = ["ISSUED"]
}

# ── 신규 VPC ─────────────────────────────────────────────────

module "network" {
  source = "../../modules/network"

  vpc_cidr             = var.vpc_cidr
  vpc_name             = "${var.name_prefix}-vpc"
  name_prefix          = var.name_prefix
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  app_port             = var.app_port
  ssh_ingress_cidrs    = var.ssh_ingress_cidrs
}

# ── IAM ─────────────────────────────────────────────────────

resource "aws_iam_role" "app" {
  name = "${var.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}-instance-profile"
  role = aws_iam_role.app.name
}

resource "aws_iam_role_policy" "s3_access" {
  name = "${var.name_prefix}-s3-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [data.aws_s3_bucket.app.arn]
      },
      {
        Sid      = "ObjectReadWrite"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${data.aws_s3_bucket.app.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecr_pull" {
  name = "${var.name_prefix}-ecr-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [var.ecr_repository_arn]
      }
    ]
  })
}

# SSM 에이전트 기본 권한
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch 에이전트 권한
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "ssm_param" {
  name = "${var.name_prefix}-ssm-param-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SSMGetParameter"
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = ["arn:aws:ssm:*:*:parameter/jeonlog/*"]
    }]
  })
}

# 이미지 URL (GitHub Actions가 배포 시 업데이트 → Instance Refresh로 새 인스턴스에 적용)
resource "aws_ssm_parameter" "ecr_image_url" {
  name  = "/jeonlog/prod/ecr-image-url"
  type  = "String"
  value = var.ecr_image_url != null ? var.ecr_image_url : "PLACEHOLDER"

  lifecycle {
    ignore_changes = [value]
  }
}

# ── RDS (스냅샷 복원) ────────────────────────────────────────
# 스냅샷에서 복원 시 engine/storage/username은 스냅샷에서 자동 상속
# db_password는 복원 후 재설정됨

resource "aws_db_instance" "jeonlog" {
  identifier = var.db_identifier

  snapshot_identifier = var.db_snapshot_identifier
  instance_class      = var.db_instance_class
  password            = var.db_password

  db_subnet_group_name   = module.network.rds_subnet_group_name
  vpc_security_group_ids = [module.network.rds_security_group_id]

  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 7
  backup_window           = "03:00-04:00"

  tags = {
    Name = "${var.name_prefix}-rds"
  }
}

# ── ALB ─────────────────────────────────────────────────────

module "alb" {
  source = "../../modules/alb"

  name_prefix         = var.name_prefix
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.public_subnet_ids
  security_group_id   = module.network.alb_security_group_id
  app_port            = var.app_port
  health_check_path   = var.health_check_path
  acm_certificate_arn = data.aws_acm_certificate.this.arn
  alb_logs_bucket     = aws_s3_bucket.alb_logs.bucket
}

# ── CloudWatch Log Groups ────────────────────────────────────

resource "aws_cloudwatch_log_group" "docker" {
  name              = "/ec2/jeonlog/docker"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "syslog" {
  name              = "/ec2/jeonlog/syslog"
  retention_in_days = 14
}

# ── ASG ─────────────────────────────────────────────────────

module "asg" {
  source = "../../modules/asg"

  name_prefix           = var.name_prefix
  ami_id                = var.ami_id
  instance_type         = var.instance_type
  key_name              = var.key_name
  instance_profile_name = aws_iam_instance_profile.app.name
  security_group_id     = module.network.app_security_group_id
  subnet_ids            = [module.network.public_subnet_ids[0]]
  target_group_arn      = module.alb.target_group_arn
  min_size              = var.min_size
  max_size              = var.max_size
  desired_capacity      = var.desired_capacity
  user_data = templatefile("${path.module}/scripts/user_data.sh", {
    s3_bucket = data.aws_s3_bucket.app.bucket
    app_port  = var.app_port
  })
}
