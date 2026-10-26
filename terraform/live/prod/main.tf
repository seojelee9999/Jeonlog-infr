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
