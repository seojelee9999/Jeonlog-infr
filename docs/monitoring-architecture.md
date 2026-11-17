# 모니터링 개선 설계

기존 Prometheus·Grafana 운영 경험을 바탕으로 관리 접근, 캐시 분리, 알림과 복구 경로를 보완한 설계안입니다. **현재 배포 완료 상태를 나타내지 않으며**, Terraform과 실제 운영 이력은 각각 [코드 기준 설계](architecture.md), [운영 변경 기록](operations-history.md)에서 확인할 수 있습니다.

## 구성과 선택 이유

| 구성 | 배치·실행 방식 | 선택 이유 |
| --- | --- | --- |
| Prometheus·Grafana | Private Subnet의 전용 EC2, Docker Compose | 기존 운영 도구를 유지하며 애플리케이션과 모니터링 자원 분리 |
| Redis | Private Subnet의 별도 EC2, Docker | 모니터링 작업과 캐시의 메모리 경합·장애 범위 분리 |
| 관리자 접근 | Session Manager 포트 포워딩 | 모니터링 EC2의 Public IP와 SSH 인바운드 없이 Grafana 조회 |
| 메트릭 저장 | Prometheus 데이터 경로를 EBS에 마운트 | 컨테이너 재생성 후에도 수집 데이터 유지 |
| 대시보드·설정 | Grafana 데이터는 EBS, provisioning·규칙은 Git | 상태 보존과 설정 재현 |
| 로그·AWS 지표 | CloudWatch Logs·Metrics, ALB 접근 로그는 S3 | 기존 AWS 수집 경로를 활용하고 Grafana에서 함께 조회 |

서비스 규모를 고려해 모니터링은 단일 EC2로 시작합니다. Redis 분리와 NAT 도입으로 추가 비용이 발생하므로 비용 절감 성과로 표현하지 않습니다. 모니터링 이중화와 Redis 복제·자동 장애 조치는 이 설계의 범위에 포함하지 않습니다.

## 통신 경로

| 출발 → 목적지 | 경로 | 접근 제한 |
| --- | --- | --- |
| 관리자 → Grafana | 로컬 포트 → Session Manager → 모니터링 EC2의 `127.0.0.1:3000` | IAM 세션 권한과 Grafana 로그인, 컨테이너 포트는 루프백에만 게시 |
| 모니터링 EC2의 SSM Agent → Systems Manager | NAT Gateway를 통한 HTTPS 아웃바운드 | EC2 관리 역할, 관리자 IAM 권한, SSM Agent 및 로컬 Session Manager 플러그인 준비 |
| Prometheus → Node Exporter | EC2 Private IP의 TCP 9100 | 애플리케이션 SG에서 모니터링 SG만 허용 |
| Prometheus → WAS Actuator | EC2 Private IP의 별도 관리 포트 | 모니터링 SG만 허용, 공개 Nginx 경로에서 `/actuator` 차단 |
| Grafana → Prometheus | Docker 내부 네트워크의 TCP 9090 | Prometheus 호스트 포트 게시 생략 |
| Prometheus → EC2 API | HTTPS, ASG 태그로 대상 탐색 | EC2 조회용 IAM 권한 |
| Grafana → CloudWatch API | HTTPS, 지표·로그 조회 | 대상 로그 그룹과 필요한 읽기 작업으로 IAM 권한 제한 |
| WAS → Redis | Private IP의 TCP 6379 | 캐시 SG에서 앱 SG만 허용, Redis 인증 설정 |

모니터링 EC2의 SG에는 관리자용 22·3000·9090 인바운드를 열지 않습니다. SSM Agent가 시작한 연결을 통해 포트 포워딩 세션을 사용합니다. Grafana 웹 로그인은 터널을 통한 접근에서도 유지합니다. [AWS Session Manager 포트 포워딩](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html)

Prometheus는 호스트 자원 확인을 위해 Node Exporter를 수집하고, WAS의 요청량·오류율·지연과 JVM 상태는 Actuator로 수집합니다. Node Exporter 컨테이너는 호스트의 `/proc`, `/sys` 등 필요한 경로를 읽기 전용으로 연결하도록 구성합니다. EC2 한 대에 WAS가 여러 개라면 관리 포트와 인스턴스 라벨을 분리하고 각 대상을 수집합니다. 부하 분산된 Nginx 주소 하나만 스크랩하면 컨테이너별 시계열을 안정적으로 구분할 수 없습니다.

EC2 Service Discovery에는 ASG 태그 필터와 Private IP를 사용합니다. 고정된 관리 포트는 포트별 수집 job으로 표현하고, 동적으로 바뀌는 컨테이너 대상은 배포 과정에서 수집 대상 목록을 갱신하도록 연결해야 합니다. [Prometheus 수집 설정](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)

## 프라이빗 서버의 아웃바운드

기본 설계는 **Private Subnet → Public Subnet의 NAT Gateway → Internet Gateway → AWS API·이미지 레지스트리·알림 서비스** 경로입니다. NAT는 아웃바운드용이며 사용자 요청이나 Prometheus의 VPC 내부 수집 경로에 들어가지 않습니다. RDS용 서브넷에는 NAT 기본 경로를 추가할 필요가 없으므로 서버용 프라이빗 서브넷과 라우팅 테이블을 분리합니다.

이 경로로 SSM 세션, EC2 자동 탐색, CloudWatch 조회, Docker 이미지 다운로드와 외부 알림 전송을 처리합니다. NAT의 AZ 배치와 수량은 비용·장애 허용 범위에 따라 정하며, 단일 NAT 선택 시 해당 AZ 장애가 외부 통신에 미치는 영향을 고려합니다.

인터넷 아웃바운드를 없애려면 SSM 외에도 EC2·CloudWatch·ECR 등 사용하는 API의 VPC 엔드포인트, 이미지 레이어용 S3 접근 경로, 공개 이미지의 ECR 사전 반입과 알림 경로를 함께 설계해야 합니다. SSM 엔드포인트만으로 이미지 다운로드와 모든 AWS API 호출이 해결되지는 않습니다. [AWS Session Manager 네트워크 요구사항](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-privatelink.html)

Prometheus와 Grafana가 EC2 IAM 역할의 임시 자격 증명을 사용할 수 있도록 컨테이너에서 IMDSv2 접근도 검증합니다. 정적 AWS 키를 이미지나 Compose 파일에 넣지 않습니다. [Grafana CloudWatch 데이터소스 설정](https://grafana.com/docs/grafana/latest/datasources/aws-cloudwatch/configure/)

## 알림과 복구

- **서비스 알림:** Grafana Alerting에서 오류율, 응답 지연, 디스크 여유 공간과 수집 실패를 평가합니다. 임계값·지속 시간·수신 채널은 운영 기준에 맞춰 정의하고 No Data·평가 오류 처리도 설정합니다.
- **모니터링 서버 장애:** EC2 상태 검사 실패는 CloudWatch Alarm에서 SNS로 전달합니다. 이 경로는 모니터링 EC2가 중단되어도 동작합니다. EC2 상태 검사만으로 Prometheus·Grafana 프로세스 장애까지 검출할 수는 없습니다.
- **프로세스 복구:** Docker 재시작 정책과 서비스 상태 검사를 구성합니다. 컨테이너가 unhealthy 상태가 되는 것만으로 Docker가 자동 재시작하지는 않으므로, 복구 절차를 별도로 정합니다.
- **데이터 복구:** EBS에 Prometheus·Grafana 데이터를 보관하고 정기 스냅샷을 생성합니다. Grafana DB 등은 일관성을 확보하는 백업 절차를 적용하고, 볼륨 복원과 설정 재적용을 연습합니다. 단순 Docker 볼륨 생성만으로 인스턴스 종료 후 보존·복구가 보장되지는 않습니다.
- **저장 용량:** Prometheus 보존 기간은 기존 설정의 15일을 시작점으로 삼고 수집량에 맞춰 용량을 조정합니다. 디스크 부족 알림과 백업 보존 정책을 함께 설정합니다.

## 코드 반영 시 필요한 변경

1. 모니터링 EC2의 서브넷·Public IP·SG를 변경하고, 서버용 프라이빗 라우팅과 NAT 경로를 추가합니다.
2. Redis를 별도 EC2로 옮기고 데이터 이관·접속 설정 변경·복구 절차를 준비합니다.
3. SSM Agent·IAM과 Grafana 루프백 바인딩을 구성하고 관리자 포트 포워딩을 검증합니다.
4. Node Exporter·WAS 관리 포트와 Prometheus 수집 대상을 구성하고 공개 경로에서 관리 엔드포인트가 차단되는지 확인합니다.
5. Grafana 데이터소스·대시보드·알림, CloudWatch Alarm·SNS, EBS 백업을 코드로 관리합니다.
6. 인스턴스 교체 시 자동 탐색, 로그 조회, 테스트 알림, 모니터링 중단 알림 및 백업 복원을 확인합니다.

이 항목들은 적용·검증 계획이며 완료된 운영 성과가 아닙니다.
