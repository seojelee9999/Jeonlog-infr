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
