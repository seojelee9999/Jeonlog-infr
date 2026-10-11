# 검증 기록

검증일: **2026-10-11 (Asia/Seoul)**

대상: 기존 `841c6d9` 기준 코드에 포트폴리오 문서, 모니터링 포트 수정, 검증 자동화를 추가한 로컬 작업본입니다. 이 기록은 운영 배포 성공 기록이 아닙니다.

## 환경과 결과

- Linux amd64
- Terraform `1.15.8`
- AWS provider `6.40.0` — 두 스택의 기존 lock 파일 사용

| 확인 항목 | 결과 | 검증 범위 |
| --- | --- | --- |
| `terraform fmt -check -recursive terraform` | 통과 | Terraform 파일 형식 |
| `bash -n` — prod 스크립트 2개 | 통과 | Bash 구문, 실제 명령 실행 아님 |
| ECR `init -backend=false -input=false -lockfile=readonly` 및 `validate` | 통과 | provider 설치 및 구성 일관성 |
| prod `init -backend=false -input=false -lockfile=readonly` 및 `validate` | 통과, 최종 경고 없음 | network·alb·asg 모듈 포함 구성 일관성 |
| Grafana template 렌더링 | 통과 | `app_port=8080`, `app_port=5000` 각각 반영 확인, 렌더링 후 Bash 구문 검사 |

최종 구성 검증 출력:

```text
Validating ecr
Success! The configuration is valid.

Validating prod
Success! The configuration is valid.
```

실행 명령:

```bash
bash scripts/validate.sh
```

검증 환경의 샌드박스에서 provider 다운로드 및 프로세스 통신이 제한되어, 승인된 환경에서 같은 검증 스크립트를 실행했습니다. `plan`, `apply`, `destroy` 또는 AWS 운영 자원 조회는 수행하지 않았습니다.

## 이번 정리에서 수정한 내용

1. Prometheus 앱 수집 포트의 고정값 `5000`을 Terraform의 `app_port` 입력과 연결했습니다. 실제 앱·보안그룹 포트와 수집 설정을 일치시키기 위한 변경입니다.
2. provider가 중복으로 경고한 Instance Refresh의 `triggers = ["launch_template"]`를 제거했습니다. Launch Template 변경은 기본 refresh 대상입니다.
3. 기존 Terraform 형식을 정리하고, 로컬과 GitHub Actions에서 같은 검증 스크립트를 사용하도록 구성했습니다.
4. ALB 접속 안내 및 모니터링 스택 설명을 현재 코드와 맞췄습니다.

## 아직 검증하지 않은 항목

| 항목 | 현재 상태 |
| --- | --- |
| 실제 AWS 계정에서의 plan/apply | 미실행 |
| GitHub Actions workflow | 파일 추가 완료, 원격 실행 미확인 |
| AMI 부팅부터 앱 실행까지 | 준비된 AMI 필요, 이번 검증에서는 미실행 |
| OIDC 인증·이미지 push·SSM 갱신·ASG refresh 전체 경로 | 외부 앱 CI 필요, 이번 검증에서는 미실행 |
| ALB·DNS·TLS·RDS 연결 | 실제 환경 검증 미실행 |
| 수정된 Prometheus 설정의 실제 수집 | 템플릿 검사만 완료, 운영 적용 미실행 |
| 부하·자동 확장·무중단 배포·rollback·백업 복원 | 결과 자료 없음 |

`validate`는 원격 서비스나 실제 자원 상태를 검증하지 않습니다. [공식 명령 설명](https://developer.hashicorp.com/terraform/cli/commands/validate)에 따라 구성 검증과 운영 검증을 구분합니다.

## 기존 운영 자료

[Grafana 화면](grafana-dashboard.png)은 기존 저장소에 있던 자료를 유지했습니다. 수집된 지표가 표시된 화면이라는 범위로 사용하며, 이번 코드 수정의 운영 검증 결과로 사용하지 않습니다.
