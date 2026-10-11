# ── 모니터링 EC2 (prod 스택에 포함) ────────────────────────────

# Grafana EC2용 보안그룹
resource "aws_security_group" "grafana" {
  name        = "${var.name_prefix}-grafana-sg"
  description = "Grafana (3000) + Prometheus (9090) + SSH"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "Grafana UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.grafana_allowed_cidrs
  }

  ingress {
    description = "Prometheus UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.grafana_allowed_cidrs
  }

  dynamic "ingress" {
    for_each = length(var.ssh_ingress_cidrs) > 0 ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_ingress_cidrs
    }
  }

  ingress {
    description     = "App ASG to Redis on Grafana EC2"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.network.app_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-grafana-sg"
  }
}

# Grafana(베스천) → RDS MySQL 접속 허용
resource "aws_security_group_rule" "rds_allow_mysql_from_grafana" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = module.network.rds_security_group_id
  source_security_group_id = aws_security_group.grafana.id
  description              = "Bastion (Grafana EC2) to RDS MySQL"
}

# Grafana → App EC2 Node Exporter(9100) 스크랩 허용
resource "aws_security_group_rule" "app_allow_node_exporter_from_grafana" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = module.network.app_security_group_id
  source_security_group_id = aws_security_group.grafana.id
  description              = "Prometheus (Grafana EC2) scrape Node Exporter"
}

# Grafana → App EC2 Spring Actuator 스크랩 허용
resource "aws_security_group_rule" "app_allow_actuator_from_grafana" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  security_group_id        = module.network.app_security_group_id
  source_security_group_id = aws_security_group.grafana.id
  description              = "Prometheus (Grafana EC2) scrape Spring Actuator"
}

# Grafana IAM Role — CloudWatch 읽기 + EC2 서비스 디스커버리
resource "aws_iam_role" "grafana" {
  name = "${var.name_prefix}-grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "grafana" {
  name = "${var.name_prefix}-grafana-profile"
  role = aws_iam_role.grafana.name
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch_read" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# Prometheus EC2 서비스 디스커버리용 (ASG 인스턴스 IP 자동 탐색)
resource "aws_iam_role_policy" "grafana_ec2_sd" {
  name = "${var.name_prefix}-grafana-ec2-sd"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
      Resource = ["*"]
    }]
  })
}

# Grafana EC2 인스턴스
resource "aws_instance" "grafana" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  key_name                    = var.key_name
  subnet_id                   = module.network.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.grafana.id]
  iam_instance_profile        = aws_iam_instance_profile.grafana.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/scripts/grafana_setup.sh", {
    asg_name               = "${var.name_prefix}-asg"
    aws_region             = var.aws_region
    app_port               = var.app_port
    grafana_admin_password = var.grafana_admin_password
    redis_password         = var.redis_password
  })

  tags = {
    Name = "${var.name_prefix}-grafana"
  }
}
