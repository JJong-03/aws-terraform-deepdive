# Terraform Deepdive — AWS Infrastructure Missions

<div align="center">
  <img src="https://img.shields.io/badge/Terraform-151515?style=for-the-badge&logo=terraform&logoColor=7B42BC" alt="Terraform" />
  <img src="https://img.shields.io/badge/AWS-151515?style=for-the-badge&logo=amazonwebservices&logoColor=FF9900" alt="AWS" />
  <img src="https://img.shields.io/badge/Amazon_SNS-151515?style=for-the-badge&logo=amazonsqs&logoColor=FF9900" alt="SNS" />
  <img src="https://img.shields.io/badge/Amazon_SQS-151515?style=for-the-badge&logo=amazonsqs&logoColor=FF4F8B" alt="SQS" />
  <img src="https://img.shields.io/badge/Redis-151515?style=for-the-badge&logo=redis&logoColor=DC382D" alt="Redis" />
  <img src="https://img.shields.io/badge/Secrets_Manager-151515?style=for-the-badge&logo=amazonaws&logoColor=FF9900" alt="Secrets Manager" />
</div>

<br/>

> **Mission 1~5에 걸쳐 AWS 기반 애플리케이션 인프라를 Terraform으로 단계적으로 구축하고, 최종적으로 재사용 가능한 모듈 구조로 리팩토링한 학습 프로젝트입니다.**
> 네트워킹 기반 구축부터 시크릿 관리, 비동기 메시징, Redis 캐시 레이어, 그리고 modules + 환경 분리까지 실무 흐름에 가까운 구조로 진행했습니다.

---

## Overview

| 항목 | 내용 |
|---|---|
| 목표 | AWS 인프라를 미션 단위로 단계 구축 → 모듈화 리팩토링 |
| 리전 | us-east-2 (Ohio) |
| 최종 구조 | `modules/` 4개 + `environments/dev` · `environments/prod` |
| 상태 관리 | S3 backend (환경별 state key 분리) |
| Terraform | >= 1.5.0 / AWS Provider ~> 5.0 |

---

## Architecture

Mission 5에서 완성된 최종 디렉토리 구조입니다.

```text
terraform-deepdive/
├── mission1-foundation/       # Mission 1 원본 (참고용)
├── mission2-secrets/          # Mission 2 원본 (참고용)
├── mission3-messaging/        # Mission 3 원본 (참고용)
├── mission4-cache/            # Mission 4 원본 (참고용)
│
└── mission5-modular/          # 최종 — modules + environments 구조
    ├── modules/
    │   ├── networking/        # VPC, Subnet, IGW, NAT, Route Table, SG, IAM
    │   ├── secrets/           # SSM Parameter Store, Secrets Manager
    │   ├── messaging/         # SNS, SQS, DLQ, Queue Policy, Subscription
    │   └── cache/             # ElastiCache Redis, Parameter Group, Subnet Group
    └── environments/
        ├── dev/               # NAT 1개, cache.t3.micro, 4일 retention
        └── prod/              # NAT 2개(AZ당), cache.r6g.large, 7일 retention
```

**모듈 체이닝 흐름:**

```text
module.networking ──→ module.cache  (private_subnet_ids, sg_redis_id)
module.secrets    ──→ module.cache  (redis_auth_token)
```

같은 root module 안에서 output → input으로 직접 전달합니다. `terraform_remote_state` 없이 단일 `terraform apply`로 전체 인프라를 관리합니다.

---

## What I Built

### Mission 1 — Foundation

후속 미션의 기반이 되는 네트워크·보안·IAM 인프라를 구성했습니다.

- VPC (DNS support / hostnames 활성화)
- Public Subnet × 2 / Private Subnet × 2 (us-east-2a, us-east-2c)
- Internet Gateway, Elastic IP, NAT Gateway
- Public / Private Route Table + Association
- Security Group 3개: `app` (HTTP/HTTPS), `redis` (6379 from app), `vpce` (443 from app)
- IAM Role + Policy (SSM Session Manager, CloudWatch Logs) + Instance Profile

### Mission 2 — Secrets

애플리케이션 설정값과 민감한 자격증명을 안전하게 관리하는 구조를 구성했습니다.

- SSM Parameter Store: app/port, app/log\_level, db/port, db/name, redis/port (5개)
- Secrets Manager: DB credentials (JSON), Redis AUTH token — 각각 별도 시크릿으로 분리
- `random_password`로 DB 비밀번호(20자), Redis AUTH token(32자) 자동 생성
- `recovery_window`를 `locals`에서 environment로 자동 계산 (dev=7일, prod=30일)
- `redis_auth_token` output에 `sensitive = true` 적용

### Mission 3 — Messaging

SNS fan-out + SQS + DLQ 기반 비동기 메시징 파이프라인을 구성했습니다.

- SNS Topic (Standard) 1개
- SQS 메인 큐 2개 (`order`, `notification`) + DLQ 2개 — `for_each` 기반
- `aws_sqs_queue_redrive_allow_policy`로 DLQ별 수신 소스 제한
- `aws_iam_policy_document` + `aws_sqs_queue_policy`로 SNS → SQS 전송 권한 제어
- SNS Subscription에 `depends_on = [aws_sqs_queue_policy.main]`으로 레이스 컨디션 방지

### Mission 4 — Cache

ElastiCache Redis를 Private Subnet에 Multi-AZ 구성으로 배포하고 보안 설정을 적용했습니다.

- ElastiCache Replication Group (Redis 7.0, primary + replica)
- Multi-AZ 배치 + Automatic Failover 활성화
- AUTH token + TLS (transit encryption) + at-rest encryption 적용
- Parameter Group: `maxmemory-policy = allkeys-lru`
- apply 후 Redis endpoint를 SSM Parameter Store에 자동 저장
- Mission 1 / Mission 2 output을 `terraform_remote_state`로 참조

### Mission 5 — Modularization

Mission 1~4의 flat 구조를 재사용 가능한 모듈로 리팩토링하고 환경을 분리했습니다.

- `modules/` 4개로 책임 분리 (networking / secrets / messaging / cache)
- `environments/dev` · `environments/prod` 디렉토리 방식 환경 분리
- `single_nat_gateway` 변수 하나로 dev(NAT 1개) / prod(NAT 2개) 리소스 수 제어
- `message_retention_seconds`를 `queues` 변수 맵에 포함해 dev(4일) / prod(7일) 차등 적용
- `recovery_window`는 secrets 모듈 내 `locals`에서 환경별 자동 계산 (외부 변수 노출 없음)
- state key를 `deepdive/mission5/dev/` · `deepdive/mission5/prod/`로 분리

---

## Skills Demonstrated

- Terraform 모듈 설계 — 입력/출력 인터페이스 정의, output → input 체이닝
- `count` vs `for_each` 선택 기준 적용 (순서 기반 리소스 vs 키 기반 리소스)
- 단일 변수(`single_nat_gateway`)로 dev/prod 리소스 수 제어
- AWS 네트워크 계층 분리 — public/private subnet, NAT, Route Table 라우팅 설계
- Security Group chaining (app → redis, app → vpce)
- 시크릿 관리 분리 — SSM Parameter Store(설정값) vs Secrets Manager(자격증명)
- ElastiCache 보안 구성 — AUTH token, TLS, at-rest encryption, Parameter Group 튜닝
- SNS fan-out + SQS DLQ + redrive policy 기반 메시징 파이프라인 구성
- backend state key 환경별 분리 전략

---

## Key Design Decisions

| 결정 | 이유 |
|---|---|
| Directory 방식 환경 분리 (vs Workspace) | `lifecycle` 블록은 동적 변수 제어 불가 — 디렉토리 방식이 환경별 커스터마이징에 명확함 |
| IAM을 networking 모듈에 포함 | EC2 Instance Profile은 네트워크 인프라와 밀접하고, 모듈 수를 4개로 유지하는 것이 학습에 적합 |
| `terraform_remote_state` 미사용 (Mission 5) | 같은 root module 안에서 직접 체이닝 — 단일 apply, 자동 변경 전파, state 간 의존성 없음 |
| `single_nat_gateway` 변수 하드코딩 (환경 main.tf) | dev/prod 각 main.tf에서 `true`/`false`로 고정 — 환경 성격을 코드에서 명시적으로 드러냄 |
| `queues` 변수를 map(object)로 설계 | 큐 추가 시 map 항목 하나만 추가하면 DLQ/Policy/Subscription까지 자동 생성 |
| `.terraform.lock.hcl` 커밋 | 팀 전체에서 동일한 프로바이더 버전으로 `terraform init` 재현성 보장 |

---

## Scope And Limitations

- **실습/학습 프로젝트**입니다. 운영 등급의 보안 강화나 모니터링 설정은 포함되어 있지 않습니다.
- EC2, ALB, RDS/Aurora는 이 저장소의 범위 밖입니다.
- `lifecycle { prevent_destroy = true }`는 학습 목적으로 개념만 다루며 코드에 구현하지 않았습니다.
- prod 환경은 `terraform plan`으로 diff 확인까지 검증되었으며, `apply`는 비용 문제로 선택 사항입니다.
- backend S3 bucket 이름은 각 `main.tf`에서 직접 교체 필요합니다 (`kjw-deepdive-bucket` placeholder).

---

## Quick Start

```bash
# 1. 저장소 클론
git clone https://github.com/<your-username>/terraform-deepdive.git
cd terraform-deepdive

# 2. backend bucket 이름 교체 (두 파일 모두)
#    mission5-modular/environments/dev/main.tf
#    mission5-modular/environments/prod/main.tf

# 3. terraform.tfvars 작성
#    각 환경 디렉토리에서 example 파일을 복사한 뒤 필요 시 수정
cp mission5-modular/environments/dev/terraform.tfvars.example \
   mission5-modular/environments/dev/terraform.tfvars
cp mission5-modular/environments/prod/terraform.tfvars.example \
   mission5-modular/environments/prod/terraform.tfvars

# 4. dev 환경 배포
cd mission5-modular/environments/dev
terraform init
terraform validate
terraform plan
terraform apply

# 5. prod 환경 검증 (apply는 선택)
cd ../prod
terraform init
terraform validate
terraform plan
```

> 자세한 준비 과정은 [Getting Started](docs/GETTING-STARTED.md)를 참고하세요.

---

## Documentation

| 문서 | 내용 |
|---|---|
| [Getting Started](docs/GETTING-STARTED.md) | 로컬 환경 준비, AWS 인증, backend 설정, 첫 `terraform apply` 절차 |
| [Architecture](docs/ARCHITECTURE.md) | 모듈 구조 상세 설명, 모듈 체이닝 흐름, dev/prod 리소스 차이표 |
| [Mission Notes](docs/MISSION-NOTES.md) | Mission 1~5 단계별 구현 포인트, 설계 판단 기록 |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | 구축 중 발생한 오류와 해결 기록 |
