resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.security_group_id]
  }

  user_data = var.user_data != "" ? base64encode(var.user_data) : null

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name_prefix}-app"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "this" {
  name                      = "${var.name_prefix}-asg"
  vpc_zone_identifier       = var.subnet_ids
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-app"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 300
    }

    triggers = ["launch_template"]
  }
}

# CPU 평균 60% 초과 시 인스턴스 자동 증가, 낮아지면 자동 감소
resource "aws_autoscaling_policy" "target_tracking" {
  name                   = "${var.name_prefix}-cpu-tracking"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  estimated_instance_warmup = 300

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}
