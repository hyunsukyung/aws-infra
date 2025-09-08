## 🧭 YOURLS on AWS Fargate

Terraform으로 **VPC + ALB + ECS(Fargate) + RDS(MySQL) + CloudFront + VPCE**를 구축하고, 컨테이너화한 **YOURLS**(단축 URL 서비스)를 고가용성·무중단 배포 아키텍처로 구현한 포트폴리오

---

**핵심 데모 포인트**
- **무중단 릴리스**: ALB **가중치 Blue/Green**(app) + **3개 서비스 롤링**(app/api/admin)
- **멀티서비스 격리**: `app / api / admin` 경로 분리 → 독립 배포·장애 격리·확장 유연성
- **자가복구·자동확장**: ALB/TG 헬스체크 + **TargetTracking**(CPU/MEM/Req/Target)로 Desired=Running 보장
- **비용 최적화**: **Fargate + Fargate Spot 혼합**, **VPCE(S3/Logs)**로 NAT 데이터 절감, **ECR Lifecycle**·**AWS Budgets**로 낭비 최소화
- **보안·거버넌스**: **OIDC 무시크릿 CI/CD**, **RDS 프라이빗**, **CloudFront OAI**, Secrets Manager 주입
- **운영 가시성**: CloudWatch **Alarms/Logs**와 간단 **Runbook**으로 상태 관찰·조치 일원화


> 🔍 **본 레포는 “데모 전용”입니다.** 인프라는 상시 구동하지 않으며, 모든 증빙은 **Docs**에서 확인합니다.  
> **Docs:** [./docs/README.md](./docs/README.md)

---

## 🔎 What’s Inside
- **네트워킹:** 3AZ VPC, Public/Private Subnets, NAT(single|per-AZ 토글), **VPC Endpoints(S3/Logs)**
- **엣지/라우팅:** ALB 경로 라우팅(`/api`, `/admin`), **CloudFront + OAI**(S3 정적)
- **컨테이너:** **ECS Fargate** 3 서비스(app/api/admin), CloudWatch Logs
- **데이터:** **RDS MySQL**(프라이빗, 파라미터 그룹), Secrets Manager 연동
- **배포·운영:** GitHub Actions **OIDC** → ECR Build/Push → ECS **롤링** & **가중치 Blue/Green**
- **가시성/안전장치:** CloudWatch **Alarms**(ALB/ECS/RDS), **App Auto Scaling**(CPU/MEM/Req/Target), **AWS Budgets**
- **IaC:** Terraform v1.6+, AWS Provider 5.x

---

## 🗂️ Repository Layout
```text
.
├─ main.tf
├─ variables.tf
├─ versions.tf
├─ outputs.tf                
├─ dev.tfvars
├─ .gitignore
├─ .github/
│  └─ workflows/
│     └─ deploy-to-ecs.yml    # OIDC 기반 빌드/푸시/롤링 배포
├─ yourls/                    # Docker build context (YOURLS + NGINX + PHP-FPM)
│  ├─ Dockerfile
│  ├─ nginx.conf
│  └─ entrypoint.sh
├─ README.md
├─ docs/                      # 증빙 문서
│  └─ results.md
└─ assets/                    # 다이어그램/이미지
   └─ architecture.png
```
## 🧩 Architecture
![architecture](./assets/architecture.png)

- **경로 라우팅**: `/* → app`, `/api/* → api`, `/admin/* → admin`  
- **가중치 Blue/Green**: `app_blue_weight` / `app_green_weight` 로 트래픽 분할  
- **NAT 절감**: S3/Logs VPCE로 이미지/로그 트래픽을 **사설 경로**로 우회

---

## 🚀 Quick Start (Optional)
> 기본 모드는 **데모 전용(무배포)** 입니다. 재현이 필요할 때만 실행하세요.
```bash
# IaC 준비
terraform init
terraform plan -var-file="dev.tfvars" -out=tfplan # 계획만 확인(비용 無)

# (선택) 실제 배포 시
# terraform apply tfplan

# GitHub Actions(OIDC) 배포 흐름
# CI/CD: main 브랜치 푸시 시 \ECR Push -> ECS 3개 서비스 롤링 -> services-stable 까지 자동 대기
```
## ✅ Demo / Verification Checklist
모든 스크린샷과 상세 로그는 Docs에 정리:
📄 ./docs/results.md
 · 🔗 https://docs.google.com/document/d/1xev0STyyOjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#heading=h.epcfztywsej0
- [ALB & CloudFront 헬스체크 200 OK](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.wvb9282fcdnh)
- [ECS 서비스 안정화(3개 서비스 정상)](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.aofduuee2joy)
- [ALB Target Groups & Target Health](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.r9if9ikv8q4c)
- [Blue/Green 가중치(트래픽 분할)](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.mlv5k175b3ap)
- [CloudWatch Logs (그룹 & tail)](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.119iznubupsy)
- [RDS(MySQL) 설정 검증](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.kekxiht9og3e)
- [VPC 엔드포인트(S3/CloudWatch)](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.kp6ls9yuf0zv)
- [ECR 이미지 & Lifecycle](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.fo5j95hc1j7t)
- [CloudWatch Alarms 요약](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.a2iq127hz5ss)
- [ECS 오토스케일(TargetTracking)](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.3serp0yqauu0)
- [Cost 가드레일 – AWS Budgets](https://docs.google.com/document/d/1xev0STyy-OjIsvBgFbZSdq8XSOYdh39qrZsXKlYBrbQ/edit?tab=t.0#bookmark=id.sli3ujyoa4ar)

## 🛠️ Operations (Runbook Lite)

> 목적: **재현 가능한 CLI**로 “서비스 안정화 상태”와 “애플리케이션 로그”를 즉시 확인

### 0) 공통 변수
```powershell
$REGION   = "ap-northeast-2"
$PROJECT = "my-platform"
$ENV = "dev"
$CLUSTER  = "$PROJECT-$ENV-cluster"

# 서비스 이름
$SVC_APP  = "$PROJECT-$ENV-svc"
$SVC_API  = "$PROJECT-$ENV-svc-api"
$SVC_ADM  = "$PROJECT-$ENV-svc-admin"
```
### 1) ECS 서비스 안정화 상태 확인
```powershell
aws ecs describe-services `
  --cluster $CLUSTER `
  --services $SVC_APP $SVC_API $SVC_ADM `
  --query 'services[].{name:serviceName, desired:desiredCount, running:runningCount, status:status, deployments:length(deployments)}' `
  --region $REGION
```
### 2) CloudWatch Logs 그룹 확인 & 최근 로그 tail
```powershell
$LG      = "/ecs/$PROJECT-$ENV"

# 로그 그룹 존재 확인
aws logs describe-log-groups `
  --log-group-name-prefix $LG `
  --query 'logGroups[].logGroupName' `
  --region $REGION
# 최근 5분 로그
aws logs tail $LG --since 5m --region $REGION
```

## 💰 Cost & ⚖️ Security Notes
- **NAT 절감**: nat_strategy(single|per_az) + S3/Logs VPC Endpoints
- 이미지/스토리지 비용 관리: ECR Lifecycle(untagged 7일, 50개 유지)
- 예산 가드레일: AWS Budgets 월 $20(예측/실사용 알림)
- 보안 기본값: RDS 프라이빗, CloudFront OAI→S3 비공개, Secrets Manager → ECS Task secrets
- CI/CD 시크릿 무노출: GitHub Actions OIDC 기반 AssumeRole

## 🧪 Tech Stack

Terraform · AWS(VPC, ALB, CloudFront, ECS Fargate, ECR, RDS MySQL, CloudWatch Logs/Alarms, App Auto Scaling, Budgets, Secrets Manager, VPCE) · GitHub Actions(OIDC) · NGINX + PHP-FPM

## 🗺️ Roadmap (문서로 계획만 제시)
 - HTTPS 종단간(ACM for ALB & CloudFront CNAME)
 - CloudFront WAF(Managed Rules)
 - ECR Interface Endpoints(ecr.api/ecr.dkr)로 NAT 0에 근접
 - CloudWatch Dashboard(한 장 요약)

## ⚠️ Notes
 - 실 계정 정보/비밀번호는 커밋 금지(예: db_password, yourls_admin_pass)
 - 장시간 미사용 리소스 비용 주의(NAT, RDS, CloudWatch Logs/CF)
 - terraform destroy 전에는 ECR 비우기(Lifecycle 또는 수동 삭제)

## 🙋 About Me
클라우드 솔루션/인프라 직무를 지향합니다. 무중단 배포·비용 최적화·보안 기본값을 실무형으로 구현하고, 증빙을 데이터로 남기는 엔지니어입니다.
문의: your.email@example.com · LinkedIn/GitHub 링크
