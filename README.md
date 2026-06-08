# Jeonlog Infrastructure

Terraform code for the Jeonlog production infrastructure on AWS.

This public package contains only reproducible infrastructure code:

- `terraform/modules`: reusable modules for `network`, `alb`, and `asg`
- `terraform/live/ecr`: ECR repository and GitHub Actions OIDC role
- `terraform/live/prod`: production VPC, ALB, ASG, RDS restore flow, and monitoring host

Sensitive runtime assets are intentionally excluded:

- `terraform.tfstate*`
- `terraform.tfvars`
- `.env*`
- `*.pem`
- service-account JSON files

## Architecture

- `network`: dedicated VPC with public subnets for ALB/app nodes and private subnets for RDS
- `alb`: HTTPS termination with ACM and ALB access logs to S3
- `asg`: launch template, rolling instance refresh, CPU target tracking
- `prod`: EC2 IAM role, SSM parameter for image rollout, RDS restore from snapshot, CloudWatch log groups
- `grafana`: separate monitoring host for Grafana, Prometheus, and Redis
- `ecr`: container registry plus GitHub Actions OIDC federation for image push and deploy automation

## Deployment Flow

1. GitHub Actions builds an image and pushes it to ECR.
2. GitHub Actions updates the SSM parameter `/jeonlog/prod/ecr-image-url`.
3. An instance refresh rolls new EC2 instances in the ASG.
4. `user_data.sh` pulls runtime files from S3, logs into ECR, and runs the application container.
5. Grafana/Prometheus scrapes Node Exporter and the Spring actuator endpoint from the app nodes.

## Repository Layout

```text
terraform/
  live/
    ecr/
    prod/
  modules/
    alb/
    asg/
    network/
```

## Usage

Use AWS credentials from a local profile, role, or environment variables.

```bash
cd terraform/live/ecr
terraform init
terraform plan

cd ../prod
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
```

## Notes

- This repo does not include remote state configuration. Add your own backend before team use.
- `terraform/live/prod/scripts/user_data.sh` expects application secrets and environment files to be stored in S3.
- `terraform/live/prod/grafana.tf` provisions a public monitoring host. Restrict `grafana_allowed_cidrs` before real use.
