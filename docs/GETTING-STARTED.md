# Getting Started

이 문서는 `mission5-modular` 기준으로 처음 배포를 시작하는 사람을 위한 안내입니다.

---

## 목차

1. [사전 준비](#1-사전-준비)
2. [AWS 인증 (MFA)](#2-aws-인증-mfa)
3. [Backend S3 Bucket 설정](#3-backend-s3-bucket-설정)
4. [변수 파일 준비](#4-변수-파일-준비)
5. [Dev 환경 배포](#5-dev-환경-배포)
6. [Prod 환경 검증](#6-prod-환경-검증)
7. [배포 후 확인](#7-배포-후-확인)
8. [리소스 정리 (Destroy)](#8-리소스-정리-destroy)
9. [주의사항](#9-주의사항)

---

## 1. 사전 준비

아래 도구가 로컬에 설치되어 있어야 합니다.

| 도구 | 버전 | 확인 명령 |
|---|---|---|
| Terraform | >= 1.5.0 | `terraform version` |
| AWS CLI | v2 | `aws --version` |
| jq | - | `jq --version` |

```bash
# Ubuntu / WSL 기준 설치
sudo apt install -y jq
```

AWS CLI 자격증명이 설정되어 있어야 합니다.

```bash
aws configure list   # 현재 설정된 profile 확인
```

---

## 2. AWS 인증 (MFA)

이 실습 환경은 MFA 인증 후 임시 자격증명을 발급받아야 합니다.  
강사가 제공한 MFA 인증 스크립트를 사용합니다.

```bash
# MFA OTP 6자리 입력 — 세션 유효시간 12시간
source ~/terraform-lab/aws-mfa-main-guide1/aws-mfa.sh <OTP 6자리>
```

인증 성공 여부 확인:

```bash
aws sts get-caller-identity
```

정상이라면 Account, UserId, Arn 정보가 출력됩니다.

> 세션 초기화가 필요한 경우:
> ```bash
> source ~/terraform-lab/aws-mfa-main-guide1/aws-mfa-clear.sh
> ```

---

## 3. Backend S3 Bucket 설정

이 프로젝트는 S3 backend로 Terraform state를 관리합니다.  
본인이 사용하는 S3 bucket 이름으로 두 파일을 수정해야 합니다.

**수정 대상 파일:**

```
mission5-modular/environments/dev/main.tf
mission5-modular/environments/prod/main.tf
```

**수정 위치:**

```hcl
backend "s3" {
  bucket = "kjw-deepdive-bucket"  # ← 이 값을 본인 bucket 이름으로 교체
  key    = "deepdive/mission5/dev/terraform.tfstate"
  region = "us-east-2"
}
```

> dev와 prod는 동일 bucket을 사용하고 `key` 경로만 다릅니다.
> - dev: `deepdive/mission5/dev/terraform.tfstate`
> - prod: `deepdive/mission5/prod/terraform.tfstate`

---

## 4. 변수 파일 준비

`terraform.tfvars`는 `.gitignore` 대상입니다.  
example 파일을 복사해서 사용합니다.

```bash
# dev
cd mission5-modular/environments/dev
cp terraform.tfvars.example terraform.tfvars

# prod
cd ../prod
cp terraform.tfvars.example terraform.tfvars
```

기본값이 이미 채워져 있으므로 대부분의 경우 수정 없이 사용 가능합니다.  
CIDR이나 캐시 설정을 바꾸고 싶다면 `terraform.tfvars`를 직접 편집합니다.

---

## 5. Dev 환경 배포

```bash
cd mission5-modular/environments/dev
```

### 5-1. 초기화

```bash
terraform init
```

프로바이더 다운로드와 모듈 등록이 완료되면 다음 단계로 넘어갑니다.

### 5-2. 문법 검증

```bash
terraform validate
```

`Success! The configuration is valid.` 출력을 확인합니다.

### 5-3. 플랜 확인

```bash
terraform plan
```

예상 결과: `Plan: ~47 to add, 0 to change, 0 to destroy`

플랜 출력에서 아래 항목을 눈으로 확인하세요.

- `module.networking` — VPC, Subnet, SG, IAM 리소스
- `module.secrets` — SSM Parameter, Secrets Manager
- `module.messaging` — SNS Topic, SQS Queue, DLQ
- `module.cache` — ElastiCache Replication Group

### 5-4. 배포

```bash
terraform apply
```

> ElastiCache Replication Group 생성에 10~15분 소요됩니다.

완료 후 output 확인:

```bash
terraform output
```

`redis_auth_token`은 sensitive로 마스킹됩니다. 직접 조회하려면:

```bash
terraform output -raw redis_auth_token
```

---

## 6. Prod 환경 검증

prod 환경은 `terraform plan`으로 dev와의 차이를 확인하는 것이 목적입니다.  
apply는 비용 문제로 선택 사항입니다.

```bash
cd mission5-modular/environments/prod

terraform init
terraform validate
terraform plan
```

플랜 출력에서 dev와 다른 부분을 확인합니다.

| 항목 | Dev | Prod |
|---|---|---|
| EIP / NAT 수 | 각 1개 | 각 2개 |
| Private Route Table 수 | 1개 | 2개 |
| `node_type` | cache.t3.micro | cache.r6g.large |
| `num_cache_clusters` | 2 | 3 |
| `snapshot_retention_limit` | 1일 | 7일 |
| `message_retention_seconds` | 345600 (4일) | 604800 (7일) |

> prod apply가 필요한 경우, `terraform.tfvars`에서 `cache_node_type = "cache.t3.micro"`로 낮춘 뒤 진행하고 완료 즉시 destroy하세요.

---

## 7. 배포 후 확인

apply 완료 후 AWS 콘솔에서 아래 항목을 확인합니다.

**VPC / Networking**
- VPC 생성 확인 (CIDR: 10.0.0.0/16)
- Public / Private Subnet 각 2개 확인 (2a, 2c)
- NAT Gateway 상태: Available

**Secrets**
- SSM Parameter Store > `/deepdive/dev/` 하위 5개 파라미터
- Secrets Manager > `deepdive/dev/db-credentials`, `deepdive/dev/redis-auth`

**Messaging**
- SNS > `KJW-deepdive-dev-sns-events` 토픽
- SQS > order, notification, order-dlq, notification-dlq 큐 4개
- SQS 구독 상태: **Confirmed**

**Cache**
- ElastiCache > Replication Group 상태: **Available**
- Nodes 탭에서 Primary / Replica가 서로 다른 AZ에 배치됐는지 확인
- Encryption (at-rest, in-transit) 모두 Enabled 확인

---

## 8. 리소스 정리 (Destroy)

실습이 끝나면 반드시 리소스를 삭제합니다.

```bash
# dev 삭제
cd mission5-modular/environments/dev
terraform destroy

# prod 삭제 (apply 했을 경우)
cd ../prod
terraform destroy
```

> `terraform destroy`는 모든 리소스를 삭제합니다.  
> 삭제 전 콘솔에서 대상 리소스를 한 번 확인하는 것을 권장합니다.

---

## 9. 주의사항

**AZ 규칙**  
`us-east-2b`는 사용하지 않습니다. `az_names`에 `us-east-2a`, `us-east-2c`만 입력하세요.

**CIDR 충돌**  
dev와 prod는 VPC CIDR이 겹쳐서는 안 됩니다.
- dev: `10.0.0.0/16`
- prod: `10.1.0.0/16`

**subnet 인덱스 순서**  
`public_subnet_cidrs[0]`은 반드시 `az_names[0]` AZ와 대응해야 합니다.  
순서가 어긋나면 prod에서 NAT Gateway와 Route Table의 AZ 매핑이 틀어집니다.

**ElastiCache auth_token**  
한 번 설정된 auth_token은 변경만 가능하고 제거할 수 없습니다.  
apply 전에 secrets 모듈이 정상 생성됐는지 확인하세요.

**State 파일 보안**  
S3 bucket에 저장되는 state 파일에는 `redis_auth_token` 등 민감한 값이 평문으로 저장됩니다.  
S3 bucket의 암호화와 접근 제어 설정을 확인하세요.

**`.terraform.lock.hcl`**  
이 파일은 커밋 대상입니다. 삭제하지 마세요. `terraform init` 시 프로바이더 버전 재현성을 보장합니다.
