## 프로젝트 명
AWS 기반 고가용성 웹 서비스 아키텍처 설계
## 프로젝트 소개
Terraform으로 ECS Fargate + ALB + RDS(MySQL) + CloudFront + VPC(public/private)을 구성하고, 컨테이너화한 YOURLS(단축 URL 서비스)를 배포하는 개인 프로젝트입니다.
## 아키텍처 상세

## 트래픽 흐름

## 설계 하이라이트 
네트워크 & 인프라
- vpc: /16, 3AZ, public/private 서브넷
- NAT 전략: nat_strategy = "single" | "per_az" (개발/운영 모드 선택)
- 라우팅: public RT -> IGW, private RT -> NATGW (또는 AZ별)
- vpc Endpoint
  - s3 gateway: private에서 s3 접근 시 NAT 우회
  - CloudWatch Logs(Interface): 로그 전송 내부화, SG로 443만 허용
- 보안 그룹
  - ALB SG: 0.0.0.0/0 :80 인바운드
  - Service SG: from ALB SG :8080만
  - DB SG: from Service SG :3306만
***
애플리케이션 & 데이터
- ECS(Fargate): app/api/admin 3개 서비스, awsvpc 네트워킹
- 컨테이너: Nginx + PHP-FPM + YOURLS
  - 헬스체크: /healthz
  - YOURLS: / 및 /api, /admin 경로
- RDS MySQL
  - 클래스 db.t4g.micro, private서브넷, 파라미터 그룹으로 UTF8MB4 설정
  - 백업/PI/모니터링은 변수로 토글
***
보안 & 시크릿 
- IAM: ECS Task Execution Role / Task Role 분리
- Secrets Manager: DB username/password를 시크릿으로 저장 -> ECS Task Definition에서 주입
- S3 OAI: CloudFront만 정적 버킷에 접근
- ECR: 이미지 스캐닝 on, Lifecycle로 미사용/오래된 이미지 정리
- RDS: 삭제 보호/스냅샷/멀티AZ는 환경에 따라 변수로 제어
***
관찰성 & 자동조정
- 로그: /ecs/<project>-<env> CloudWatch Logs(서비스 당 로그 그룹)
- 알람(CloudWatch Alarms)
  - ALB 5xx, Target UnHealthy, ECS CPU 80%, Tasks Missing, RDS CPU High, Free Storage Low
- 오토스케일(TargetTracking, app서비스)
  - ECSServiceAverageCPUUtilization = 50
  - ECSServiceAverageMemoryUtilization = 65
  - ALBRequestCountPerTarget = 100
- 비용 가드레일: Budgets 월 $20, 80%(예측)/100%(실제) 이메일 알림
***
컨테이너/이미지 & 배포
- Dockerfile: Nginx + PHP-FPM + YOURLS, entrypoint가 config.php 생성/부트
- ECR: <account>.dkr.ecr.<region>.amazonaws.com/<repo>:latest
- GitHub Actions (OIDC)
  - Role Assume -> ECR 로그인
  - Build & Push :latest
  - ecs update-service --force-new-deployment (app/api/admin)
  - services-stable 대기
- Blue/Green: ALB Listener의 forward 가중치로 점진 전환(stickness off)
***
비용/가용성 설계 포인트
- dev: NAT single, RDS 단일 AZ, CloudFront PriceClass_100, ECR lifecycle로 이미지 비용 관리, VPCE로 NAT 데이터 처리 비용 절감, Budgets로 상한 모니터링
- 가용성

## 빠른 시작

## 레포 구조

## 상세 문서 링크 모음
  
