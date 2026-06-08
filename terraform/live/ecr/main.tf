data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── GitHub Actions OIDC ──────────────────────────────────────

# GitHub OIDC Provider (계정당 1개, 이미 있으면 에러 → import 필요)
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# GitHub Actions가 assume할 IAM Role
resource "aws_iam_role" "github_actions" {
  name = "github-actions-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:jaykwon0207/Jeonlog-Backend:*",
            "repo:lastro1206/jeonlog-frontendnew:*"
          ]
        }
      }
    }]
  })
}

# ECR push/pull 권한
resource "aws_iam_role_policy" "github_actions_ecr" {
  name = "github-actions-ecr-policy"
  role = aws_iam_role.github_actions.id

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
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = [aws_ecr_repository.app.arn]
      }
    ]
  })
}

# 배포 권한 (SSM, ASG Instance Refresh)
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "github-actions-deploy-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMParameter"
        Effect = "Allow"
        Action = ["ssm:PutParameter", "ssm:GetParameter"]
        Resource = ["arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.current.account_id}:parameter/jeonlog/*"]
      },
      {
        Sid      = "SSMCommand"
        Effect   = "Allow"
        Action   = ["ssm:SendCommand", "ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
        Resource = ["*"]
      },
      {
        Sid      = "EC2Describe"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = ["*"]
      },
      {
        Sid    = "ASGRefresh"
        Effect = "Allow"
        Action = [
          "autoscaling:StartInstanceRefresh",
          "autoscaling:DescribeInstanceRefreshes",
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_ecr_repository" "app" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = var.repository_name }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "dev 이미지: 최근 3개만 유지"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev-"]
          countType     = "imageCountMoreThan"
          countNumber   = 3
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "prod 이미지: 최근 10개 유지"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 3
        description  = "태그 없는 이미지: 1일 후 삭제"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}
