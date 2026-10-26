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
