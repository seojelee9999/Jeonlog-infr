resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# ──────────────────────────────────────────────
# Public Subnets (ALB + ASG 노드)
# map_public_ip_on_launch = true → EC2에 Public IP 자동 부여
# NAT 없이 인터넷 아웃바운드 가능
# ──────────────────────────────────────────────
resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-${substr(var.azs[count.index], -1, 1)}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ──────────────────────────────────────────────
# Private Subnets (RDS 전용)
# 아웃바운드 라우트 없음 → 완전 격리
# RDS가 이미 존재하면 해당 RDS에 이 서브넷 그룹을 연결해야 함
# ──────────────────────────────────────────────
resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.name_prefix}-private-${substr(var.azs[count.index], -1, 1)}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  # 아웃바운드 default route 없음 — RDS는 인터넷 불필요

  tags = {
    Name = "${var.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ──────────────────────────────────────────────
# Security Groups
# 트래픽 흐름: Internet → ALB SG → App SG → RDS SG
# ──────────────────────────────────────────────

# ALB: 인터넷에서 HTTP/HTTPS 수신
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Allow HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }
}

# App (Spring): ALB에서 오는 트래픽 + 선택적 SSH 허용
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "Allow traffic from ALB, optional SSH"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Spring app port from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-app-sg"
  }

  lifecycle {
    ignore_changes = [ingress]
  }
}

# RDS: App 노드에서 오는 MySQL 트래픽만 허용
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Allow MySQL from App nodes only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "MySQL from app nodes"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-rds-sg"
  }

  lifecycle {
    ignore_changes = [ingress]
  }
}

# ──────────────────────────────────────────────
# RDS DB Subnet Group
# RDS가 이미 존재해도 새 VPC에 마이그레이션 시 필요
# ──────────────────────────────────────────────
resource "aws_db_subnet_group" "rds" {
  name        = "${var.name_prefix}-rds-subnet-group"
  description = "Private subnets for RDS (MySQL)"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name = "${var.name_prefix}-rds-subnet-group"
  }
}
