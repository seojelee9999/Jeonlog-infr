# Jeonlog Infrastructure

AWS 상에 Jeonlog 운영 인프라를 구성하기 위한 Terraform 코드입니다.

이 공개 저장소에는 재현 가능한 인프라 코드만 포함되어 있습니다.

- `terraform/modules`: `network`, `alb`, `asg` 공통 모듈
- `terraform/live/ecr`: ECR 저장소와 GitHub Actions OIDC 역할
- `terraform/live/prod`: 운영 VPC, ALB, ASG, RDS 복원 흐름, 모니터링 서버

민감한 운영 파일은 의도적으로 제외했습니다.

- `terraform.tfstate*`
- `terraform.tfvars`
- `.env*`
- `*.pem`
- 서비스 계정 JSON 파일

## 아키텍처

- `network`: ALB와 앱 EC2를 위한 퍼블릭 서브넷, RDS를 위한 프라이빗 서브넷을 포함한 전용 VPC
- `alb`: ACM 인증서를 사용한 HTTPS 종료와 ALB 액세스 로그 S3 적재
- `asg`: Launch Template, Rolling Instance Refresh, CPU Target Tracking 기반 오토스케일링
- `prod`: EC2 IAM Role, 이미지 배포용 SSM Parameter, RDS 스냅샷 복원, CloudWatch 로그 그룹 구성
- `grafana`: Grafana, Prometheus, Redis를 분리된 모니터링 EC2에 구성
- `ecr`: 컨테이너 이미지 저장소와 GitHub Actions 배포 자동화를 위한 OIDC 연동

## 배포 흐름

1. GitHub Actions가 애플리케이션 이미지를 빌드해 ECR에 푸시합니다.
2. GitHub Actions가 `/jeonlog/prod/ecr-image-url` SSM 파라미터를 갱신합니다.
3. ASG의 Instance Refresh가 실행되어 새 인스턴스로 점진 교체됩니다.
4. `user_data.sh`가 S3에서 런타임 파일을 가져오고, ECR 로그인 후 애플리케이션 컨테이너를 실행합니다.
5. Grafana와 Prometheus가 앱 EC2의 Node Exporter 및 Spring Actuator 메트릭을 수집합니다.

## 저장소 구조

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

## 사용 방법

AWS 자격 증명은 로컬 프로파일, IAM Role, 또는 환경 변수 방식으로 준비해야 합니다.

```bash
cd terraform/live/ecr
terraform init
terraform plan

cd ../prod
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
```

## 참고 사항

- 이 저장소에는 remote state 설정이 포함되어 있지 않습니다. 실제 협업 환경에서는 backend를 별도로 구성해야 합니다.
- `terraform/live/prod/scripts/user_data.sh`는 애플리케이션 환경 파일과 비밀 파일이 S3에 저장되어 있다고 가정합니다.
- `terraform/live/prod/grafana.tf`는 퍼블릭 모니터링 EC2를 생성하므로, 실제 운영 전에는 `grafana_allowed_cidrs`를 제한하는 것이 좋습니다.
