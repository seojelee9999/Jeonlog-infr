# 아키텍처와 설계 검토

이 문서는 **저장소에 보존된 Terraform 구성**을 설명합니다. 실제 운영 중 수행한 ALB 제거와 Grafana의 비공개 접근·네트워크 배치 변경은 [운영 변경 기록](operations-history.md)에 분리했습니다. 아래 설명을 서비스 종료 시점의 최종 구성으로 해석하지 않습니다.

## 구성 경계

| 스택·모듈 | 책임 |
| --- | --- |
| `live/ecr` | ECR, 이미지 보존 정책, GitHub OIDC 및 배포 역할 |
| `live/prod` | 모듈 조합, RDS 스냅샷 복원, EC2 역할, SSM, 로그, 모니터링 EC2 |
| `modules/network` | VPC, public/private subnet, 라우팅, SG, DB subnet group |
| `modules/alb` | HTTP→HTTPS 리다이렉트, ACM 연결, Target Group 및 health check |
| `modules/asg` | Launch Template, ASG, Instance Refresh, CPU Target Tracking |

두 root stack은 state가 분리됩니다. prod는 ECR ARN을 입력으로 받으며, remote state 연결이나 backend 구성은 없습니다.

## 요청·데이터 흐름

외부 요청은 ALB의 HTTPS listener에서 종료한 뒤 앱 포트로 전달됩니다. ALB의 공개 DNS 이름은 DNS 연결 대상이며, HTTPS 요청에는 ACM 인증서와 일치하는 애플리케이션 도메인이 필요합니다.

앱 SG는 ALB SG로부터 앱 포트 접근을 허용하고, DB SG는 앱 SG로부터 MySQL 접근을 허용합니다. 별도 규칙으로 모니터링 EC2의 Node Exporter·Actuator 수집 및 DB 관리 접근을 허용합니다. Redis는 모니터링 EC2에서 실행하며 앱 SG의 6379 접근을 허용합니다.

현재 ASG에 전달하는 서브넷은 `module.network.public_subnet_ids[0]` 하나입니다. ALB와 서브넷의 다중 AZ 구성만으로 애플리케이션 전체가 다중 AZ로 동작한다고 설명할 수 없습니다. RDS의 Multi-AZ도 코드에서 명시적으로 활성화하지 않습니다.

## 배포·확장·관측

- Instance Refresh는 정상 인스턴스 최소 비율 100%, 최대 비율 200%, warmup 300초로 구성합니다. 실제 무중단 결과는 별도 검증이 필요합니다.
- 평균 CPU 목표값은 60%입니다. 요청 지연·DB 부하·메모리 압박을 직접 반영하는 확장 정책은 아닙니다.
- SSM 이미지 URL은 Terraform 초기 생성 후 외부 CI가 갱신합니다. SSM 값 갱신과 ASG refresh 실행은 별도 작업입니다.
- Prometheus는 ASG 태그로 Node Exporter 9100 및 앱의 `/actuator/prometheus`를 수집하도록 구성합니다.
- 앱 수집 포트는 `app_port`를 사용합니다. 이전의 고정값 5000과 기본 앱 포트 8080의 불일치를 제출 준비 과정에서 수정했습니다.
- CloudWatch 로그 보존은 컨테이너 로그 30일, syslog 14일이며, ALB 접근 로그의 S3 보존은 30일입니다.

## 선택의 효과와 제약

| 현재 선택 | 얻는 효과 | 감수하는 제약 |
| --- | --- | --- |
| Public Subnet에 앱 배치, NAT 없음 | 구성 요소를 줄이고 직접 인터넷 아웃바운드 제공 | public IP 및 인바운드 통제 관리 필요; 비용 절감량은 미측정 |
| 모니터링 서버에 Grafana·Prometheus·Redis 공존 | 적은 인스턴스로 기능 통합 | 자원 경합, Redis와 관측 환경의 장애 범위 공유 |
| 준비된 AMI + 부팅 시 이미지 실행 | 부팅 스크립트의 설치 작업 축소 | AMI 구성·패치 과정이 저장소 밖에 있음 |
| 기존 RDS snapshot으로 복원 | 기존 데이터로 새 DB 생성 가능 | 복원 시점·데이터 누락·실제 RTO/RPO 검증 필요 |
| S3에서 런타임 설정 읽기 | 실행 설정을 앱 이미지와 분리 | 권한·감사·암호화·비밀 회전 절차 필요 |

이 표는 현재 코드의 효과와 한계를 분석한 것이며, 당시 결정 이유를 기록한 ADR을 대신하지 않습니다.

## 개선 우선순위

### 운영 적용 전에 확인할 항목

- **관리 접근:** `grafana_allowed_cidrs` 기본값은 `0.0.0.0/0`입니다. 관리자 CIDR로 제한하고 Grafana/Prometheus의 TLS·인증 경로를 정합니다.
- **State·비밀:** `sensitive = true`는 state나 EC2 user data에서 비밀을 제거하지 않습니다. 암호화된 원격 state, 접근 제어, 잠금과 비밀 공급 방식을 설계해야 합니다.
- **OIDC·IAM:** 신뢰 대상이 특정 GitHub 저장소에 하드코딩되어 있으며 브랜치 범위가 `*`입니다. 실제 배포 브랜치·환경으로 제한하고 SSM/ASG 권한 범위를 검토합니다.
- **DB·로그 삭제:** RDS는 `skip_final_snapshot = true`, ALB 로그 버킷은 `force_destroy = true`입니다. 운영 데이터를 보존할 정책을 정한 뒤 변경 계획을 검토합니다.
- **SG 관리:** inline ingress와 별도 SG rule, `ignore_changes = [ingress]`가 함께 사용됩니다. 규칙 소유권을 단일 방식으로 정리하고 drift 검출을 확인해야 합니다.

### 가용성·재현성 개선

- 앱 ASG의 다중 AZ 배치와 실제 AZ 장애 검증
- Redis 분리 및 복구 계획, 모니터링 스토리지 백업
- AMI 빌드 코드와 애플리케이션 CI workflow 연결
- Prometheus/Grafana 버전 고정, dashboard JSON과 알림 규칙 관리
- 배포 실패 감지·rollback 자동화 및 실패 주입 검증
- 부하 테스트, 배포 중 오류율·지연, 확장 시간·비용 측정

위 항목들은 개선 계획이며 구현 완료 성과로 표시하지 않습니다.
