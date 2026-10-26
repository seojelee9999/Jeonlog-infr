# 실행 준비와 운영 확인

이 문서는 재현에 필요한 의존성과 점검 순서를 설명합니다. 실제 실행 결과는 [검증 기록](verification.md)과 구분합니다.

## 1. 선행 자원

| 의존성 | 필요한 상태 |
| --- | --- |
| AWS 인증 | 대상 계정·리전을 확인한 프로파일 또는 IAM 역할 |
| 기존 S3 | 앱에서 사용할 버킷과 `config/.env.prod.properties`, `secrets/firebase-service-account.json` |
| ACM | 대상 리전에 발급 완료된 도메인 인증서 |
| RDS snapshot | 대상 계정·리전에서 읽을 수 있는 복원 출발점 |
| EC2 key pair | `key_name`에 해당하는 기존 키페어 |
| 준비된 Ubuntu AMI | `ubuntu` 사용자, Docker/Compose, AWS CLI, CloudWatch Agent, Node Exporter 설치·서비스 설정 |
| 애플리케이션 | `app_port`에서 수신, health 및 Prometheus endpoint 제공, 런타임 설정과 호환 |
| GitHub CI | OIDC 신뢰 정책의 저장소와 일치하는 앱 저장소 및 배포 workflow |

현재 부팅 스크립트에는 위 패키지 설치 과정이 없습니다. 기본 Ubuntu AMI만 입력해서 모든 기능이 준비된다고 가정하지 않습니다. AMI를 재현하는 별도 빌드 코드는 포함되지 않습니다.

## 2. 코드 검증

저장소 루트에서 실행합니다.

```bash
bash scripts/validate.sh
```

`fmt`, Bash 구문 검사, `init -backend=false -lockfile=readonly`, `validate`를 수행합니다. provider 다운로드 외의 AWS 접근이나 자원 변경은 없습니다.

## 3. 환경별 plan 준비

샘플을 복사해 실제 환경값을 설정합니다. `change-me`와 예시 ARN·도메인·AMI는 모두 교체해야 합니다. tfvars 및 state는 커밋하지 않습니다.

```bash
cp terraform/live/ecr/terraform.tfvars.example terraform/live/ecr/terraform.tfvars
cp terraform/live/prod/terraform.tfvars.example terraform/live/prod/terraform.tfvars
```

1. `live/ecr/iam.tf`의 OIDC 신뢰 저장소·브랜치와 역할 이름을 검토합니다. 계정에 GitHub OIDC provider가 이미 있다면 import 등 기존 자원 관리 방식을 먼저 결정합니다.
2. ECR 스택의 계획을 확인합니다.

   ```bash
   terraform -chdir=terraform/live/ecr init
   terraform -chdir=terraform/live/ecr plan
   ```

3. ECR 준비 후 repository ARN과 실제 이미지 URL을 prod 입력에 반영합니다. 앱 이미지는 별도 CI가 생성해야 합니다.
4. 관리 CIDR, 비밀 공급, state 보관, DB snapshot 및 AMI 준비를 확인하고 prod 계획을 검토합니다.

   ```bash
   terraform -chdir=terraform/live/prod init
   terraform -chdir=terraform/live/prod plan
   ```

`plan`은 실제 AWS 자원을 조회합니다. 이 문서에는 자동 `apply`나 `destroy`를 포함하지 않습니다. `grafana.tf`도 prod 스택의 일부이므로 일반 prod 적용 계획에 함께 포함됩니다.

RDS 복원 후 출력되는 endpoint를 앱 런타임 설정에 반영해야 합니다. Terraform이 S3의 환경 파일 내용을 자동으로 수정하지는 않습니다. ALB 출력 DNS와 인증서 도메인의 DNS 연결도 별도로 준비합니다.

## 4. 배포 상태 확인

아래 값은 대상 환경에서 확인해 설정합니다. 조회·HTTP 확인 명령입니다.

```bash
export AWS_REGION=ap-northeast-2
export JEONLOG_ASG_NAME=jeonlog-prod-asg
export JEONLOG_APP_URL=https://api.example.com

aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$JEONLOG_ASG_NAME"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$JEONLOG_ASG_NAME" \
  --query 'AutoScalingGroups[].{Desired:DesiredCapacity,Instances:Instances[*].{Id:InstanceId,Health:HealthStatus,State:LifecycleState}}'
aws ssm get-parameter --name /jeonlog/prod/ecr-image-url \
  --query Parameter.Value --output text
curl --fail --show-error --max-time 10 "$JEONLOG_APP_URL/actuator/health"
```

정상 판단에는 refresh 성공, 기대 이미지, ASG 인스턴스 상태, ALB target health, 실제 HTTP 응답을 함께 사용합니다. health 경로를 바꿨다면 위 URL도 맞춥니다.

## 5. 실패 시 확인 순서

| 증상 | 먼저 확인할 항목 |
| --- | --- |
| 새 EC2가 앱을 실행하지 못함 | AMI의 패키지·서비스, `/var/log/user-data.log`, `/var/log/deploy.log`, S3/SSM/ECR 권한 |
| ALB target unhealthy | 앱 포트·health 경로·SG·앱 시작 시간, 컨테이너 로그 |
| DB 연결 실패 | 복원 완료 여부, 실제 endpoint가 런타임 설정에 반영됐는지, SG·자격 증명 |
| 메트릭 누락 | ASG 태그, IAM Describe 권한, exporter 상태, 수집 포트·SG, Prometheus Targets |
| 특정 버전 배포 후 오류 | 기대 이미지와 실제 이미지 비교, 앱 로그·DB 호환성, refresh 진행 상태 |

로그에는 비밀값이 포함될 수 있으므로 공개 증빙에는 원문을 그대로 올리지 않습니다.

## 6. rollback 및 복구 범위

애플리케이션 rollback은 이전 정상 이미지 URL을 SSM에 기록하고 새 Instance Refresh를 요청하는 절차가 필요합니다. 현재 저장소에는 이를 자동으로 실행하거나 실패 시 자동 복귀하는 workflow가 없습니다. 진행 중인 refresh 상태와 DB 스키마 호환성을 먼저 확인해야 합니다.

RDS snapshot 복원 코드는 데이터 복구 수단의 일부입니다. 백업 무결성, 실제 복원 시간, 앱 연결 전환까지 검증해야 복구 성공으로 기록할 수 있습니다. Redis AOF와 Docker volume도 별도 장애 복구·백업 검증을 대신하지 않습니다.

## 참고

- [Terraform validate의 범위와 backend 없는 초기화](https://developer.hashicorp.com/terraform/cli/commands/validate)
- [GitHub Actions의 Terraform 설정](https://github.com/hashicorp/setup-terraform)
