# Architecture

이 문서는 `mission5-modular` 기준 최종 아키텍처를 설명합니다.

---

## 목차

1. [전체 구조](#1-전체-구조)
2. [Mission 진행 흐름](#2-mission-진행-흐름)
3. [모듈별 책임](#3-모듈별-책임)
4. [Module Chaining](#4-module-chaining)
5. [Dev / Prod 환경 차이](#5-dev--prod-환경-차이)
6. [NAT Gateway 전략](#6-nat-gateway-전략)
7. [State / Backend 분리](#7-state--backend-분리)

---

## 1. 전체 구조

```text
terraform-deepdive/
│
├── mission1-foundation/       # 학습 원본 — 건드리지 않음
├── mission2-secrets/          # 학습 원본 — 건드리지 않음
├── mission3-messaging/        # 학습 원본 — 건드리지 않음
├── mission4-cache/            # 학습 원본 — 건드리지 않음
│
└── mission5-modular/          # 최종 구조
    ├── modules/
    │   ├── networking/
    │   │   ├── main.tf        # VPC, Subnet, IGW, EIP, NAT, Route Table, SG, IAM
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   ├── secrets/
    │   │   ├── main.tf        # SSM Parameter Store, Secrets Manager, random_password
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   ├── messaging/
    │   │   ├── main.tf        # SNS, SQS, DLQ, Queue Policy, Subscription
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   └── cache/
    │       ├── main.tf        # ElastiCache Redis, Parameter Group, Subnet Group, SSM endpoint
    │       ├── variables.tf
    │       └── outputs.tf
    └── environments/
        ├── dev/
        │   ├── main.tf        # terraform 블록 + provider + module 호출
        │   ├── variables.tf   # dev 기본값 정의
        │   ├── outputs.tf     # module output re-expose
        │   └── terraform.tfvars
        └── prod/
            ├── main.tf        # terraform 블록 + provider + module 호출
            ├── variables.tf   # prod 기본값 정의
            ├── outputs.tf     # module output re-expose
            └── terraform.tfvars
```

---

## 2. Mission 진행 흐름

Mission 1~4는 각각 독립된 flat 구조로 작성된 원본입니다.  
Mission 5는 이 원본들을 참고해 modules + environments 구조로 재구성한 최종 단계입니다.

```
Mission 1  →  기반 인프라 (VPC, SG, IAM)
Mission 2  →  시크릿 관리 (SSM, Secrets Manager)
Mission 3  →  비동기 메시징 (SNS, SQS, DLQ)
Mission 4  →  캐시 레이어 (ElastiCache Redis)
    ↓
Mission 5  →  모듈화 리팩토링 + 환경 분리
```

Mission 1~4의 코드는 참고 원본으로 보존되며, Mission 5 배포 전에 destroy합니다.  
Mission 5는 기존 state와 별도 경로를 사용해 충돌 없이 fresh deploy합니다.

---

## 3. 모듈별 책임

### modules/networking

Mission 1 범위 전체를 담당합니다. IAM(EC2 Instance Profile)을 이 모듈에 포함한 이유는, EC2 Instance Profile이 네트워크 인프라와 밀접하고 모듈 수를 4개로 유지하는 것이 학습에 적합하기 때문입니다.

| 리소스 | 설명 |
|---|---|
| `aws_vpc` | DNS support / hostnames 활성화 |
| `aws_subnet` (public × 2) | us-east-2a, us-east-2c — `count` 기반 |
| `aws_subnet` (private × 2) | us-east-2a, us-east-2c — `count` 기반 |
| `aws_internet_gateway` | Public 라우팅용 |
| `aws_eip` + `aws_nat_gateway` | `single_nat_gateway` 변수로 개수 제어 |
| `aws_route_table` (public) | IGW 라우팅 |
| `aws_route_table` (private) | NAT 라우팅 — `single_nat_gateway`로 개수 제어 |
| `aws_security_group` × 3 | app (HTTP/HTTPS), redis (6379 from app), vpce (443 from app) |
| `aws_iam_role` + `aws_iam_role_policy` | SSM Session Manager + CloudWatch Logs 권한 |
| `aws_iam_instance_profile` | EC2 Instance Profile |

**주요 입력 변수:**

| 변수 | 설명 |
|---|---|
| `vpc_cidr` | VPC CIDR 블록 |
| `az_names` | 사용 AZ 목록 (인덱스 순서가 subnet CIDR과 일치해야 함) |
| `public_subnet_cidrs` | Public subnet CIDR 목록 |
| `private_subnet_cidrs` | Private subnet CIDR 목록 |
| `single_nat_gateway` | `true` = NAT 1개(dev), `false` = AZ당 1개(prod) |

**출력:**  
`vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `sg_app_id`, `sg_redis_id`, `sg_vpce_id`, `app_role_arn`, `app_instance_profile_name`, `iam_instance_profile_arn`

---

### modules/secrets

Mission 2 범위를 담당합니다. `recovery_window`는 모듈 내 `locals`에서 `var.environment`로 자동 계산하며, 외부에 별도 변수로 노출하지 않습니다.

| 리소스 | 설명 |
|---|---|
| `random_password` (DB) | 20자, 특수문자 허용 |
| `random_password` (Redis) | 32자, 특수문자 제외 (ElastiCache AUTH 제약) |
| `aws_ssm_parameter` × 5 | app/port, app/log\_level, db/port, db/name, redis/port |
| `aws_secretsmanager_secret` (DB) | JSON: username, password, dbname |
| `aws_secretsmanager_secret` (Redis) | AUTH token 문자열 |

**환경별 자동 계산:**

```hcl
# modules/secrets/main.tf
locals {
  recovery_window = var.environment == "prod" ? 30 : 7
}
```

**출력:**  
`ssm_parameter_prefix`, `db_credentials_secret_arn`, `db_credentials_secret_name`, `redis_auth_secret_arn`, `redis_auth_token` (sensitive)

---

### modules/messaging

Mission 3 범위를 담당합니다. `queues` 변수를 `map(object)` 타입으로 받아 `for_each` 기반으로 큐를 생성합니다. 큐 추가 시 map 항목 하나만 추가하면 DLQ / Queue Policy / SNS Subscription이 자동으로 함께 생성됩니다.

| 리소스 | 설명 |
|---|---|
| `aws_sns_topic` | Standard Topic 1개 |
| `aws_sqs_queue` (main) | `for_each` — `queues` 맵의 키 기반 |
| `aws_sqs_queue` (DLQ) | `for_each` — 메인 큐와 1:1 대응 |
| `aws_sqs_queue_redrive_allow_policy` | DLQ별 수신 소스를 자신의 메인 큐 ARN으로 제한 |
| `aws_sqs_queue_policy` | SNS → SQS 전송 허용 (SourceArn 조건) |
| `aws_sns_topic_subscription` | SNS → SQS 구독 (`depends_on` queue policy) |

**`queues` 변수 구조:**

```hcl
variable "queues" {
  type = map(object({
    visibility_timeout_seconds = number
    max_receive_count          = number
    message_retention_seconds  = number  # dev/prod 차이 주입 포인트
  }))
}
```

**출력:**  
`sns_topic_arn`, `sqs_queue_urls`, `sqs_queue_arns`, `dlq_queue_arns`

---

### modules/cache

Mission 4 범위를 담당합니다. networking / secrets 모듈의 output을 직접 입력 변수로 받습니다. ElastiCache 식별자는 소문자만 허용되므로 `locals`에서 `lower()`를 적용합니다.

| 리소스 | 설명 |
|---|---|
| `aws_elasticache_parameter_group` | `maxmemory-policy = allkeys-lru` |
| `aws_elasticache_subnet_group` | `private_subnet_ids` 입력 변수로 주입 |
| `aws_elasticache_replication_group` | Multi-AZ, AUTH token, TLS, at-rest encryption |
| `aws_ssm_parameter` (redis/host) | Primary endpoint 저장 |
| `aws_ssm_parameter` (redis/reader\_host) | Reader endpoint 저장 |

**주요 입력 변수:**

| 변수 | 출처 |
|---|---|
| `private_subnet_ids` | `module.networking.private_subnet_ids` |
| `sg_redis_id` | `module.networking.sg_redis_id` |
| `redis_auth_token` | `module.secrets.redis_auth_token` |
| `node_type` | environment 변수 |
| `num_cache_clusters` | environment 변수 |
| `apply_immediately` | environment 변수 |
| `snapshot_retention_limit` | environment 변수 |

**출력:**  
`redis_primary_endpoint`, `redis_reader_endpoint`, `redis_port`, `redis_replication_group_id`, `redis_subnet_group_name`

---

## 4. Module Chaining

Mission 5는 `terraform_remote_state` 없이 같은 root module 안에서 output → input으로 직접 체이닝합니다.

```
module.networking ──→ module.cache
  private_subnet_ids
  sg_redis_id

module.secrets ──→ module.cache
  redis_auth_token
```

**environments/dev/main.tf 발췌:**

```hcl
module "cache" {
  source = "../../modules/cache"

  # networking output → cache input
  private_subnet_ids = module.networking.private_subnet_ids
  sg_redis_id        = module.networking.sg_redis_id

  # secrets output → cache input
  redis_auth_token   = module.secrets.redis_auth_token

  node_type                = var.cache_node_type
  num_cache_clusters       = var.cache_num_clusters
  apply_immediately        = var.cache_apply_immediately
  snapshot_retention_limit = var.cache_snapshot_retention
}
```

**`terraform_remote_state`를 사용하지 않은 이유:**

Mission 1~4는 각각 독립 state를 갖는 flat 구조였기 때문에 Mission 4에서 Mission 1 / 2의 output을 `terraform_remote_state`로 참조해야 했습니다. Mission 5에서는 4개 모듈이 하나의 root module(environments/dev) 아래 통합됩니다. 같은 root 안에 있으면 output을 직접 참조할 수 있으므로 `terraform_remote_state`가 불필요합니다.

이 구조의 장점:
- `terraform apply` 한 번으로 전체 인프라 관리
- 의존 모듈의 output이 바뀌면 자동으로 전파
- state 간 의존성이 없어 관리 포인트 감소

**모듈 output re-expose:**  
`terraform output`은 root module의 output만 표시합니다. 모듈 내부 output은 자동으로 노출되지 않으므로, `environments/dev/outputs.tf`와 `environments/prod/outputs.tf`에서 필요한 값을 명시적으로 re-expose합니다.

---

## 5. Dev / Prod 환경 차이

| 항목 | Dev | Prod |
|---|---|---|
| **Networking** | | |
| `vpc_cidr` | 10.0.0.0/16 | 10.1.0.0/16 |
| `single_nat_gateway` | `true` (NAT 1개) | `false` (AZ당 NAT 1개) |
| EIP 수 | 1개 | 2개 |
| NAT Gateway 수 | 1개 | 2개 |
| Private Route Table 수 | 1개 | 2개 |
| **Secrets** | | |
| `recovery_window` | 7일 (자동 계산) | 30일 (자동 계산) |
| **Messaging** | | |
| `message_retention_seconds` | 345600 (4일) | 604800 (7일) |
| **Cache** | | |
| `node_type` | cache.t3.micro | cache.r6g.large |
| `num_cache_clusters` | 2 | 3 |
| `apply_immediately` | true | false |
| `snapshot_retention_limit` | 1일 | 7일 |

**예상 리소스 수:**

| 환경 | 모듈 | 리소스 수 |
|---|---|---|
| Dev | networking | ~20 (NAT 1개 기준) |
| Dev | secrets | ~11 |
| Dev | messaging | ~11 |
| Dev | cache | ~5 |
| **Dev 합계** | | **~47** |
| Prod | networking | ~23 (NAT 2개 기준, +3) |
| Prod | secrets | ~11 |
| Prod | messaging | ~11 |
| Prod | cache | ~5 |
| **Prod 합계** | | **~50** |

---

## 6. NAT Gateway 전략

`single_nat_gateway` 변수 하나로 EIP / NAT Gateway / Private Route Table 수가 결정됩니다.

```hcl
# modules/networking/main.tf

resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.az_names)
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  count         = var.single_nat_gateway ? 1 : length(var.az_names)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
}

resource "aws_route_table" "private" {
  count  = var.single_nat_gateway ? 1 : length(var.az_names)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}
```

`single_nat_gateway`는 각 환경의 `main.tf`에서 하드코딩합니다.

```hcl
# environments/dev/main.tf
module "networking" {
  single_nat_gateway = true   # dev 고정
}

# environments/prod/main.tf
module "networking" {
  single_nat_gateway = false  # prod 고정
}
```

변수로 열어두지 않고 환경 main.tf에 명시하는 이유는, 이 값이 해당 환경의 고유한 성격(비용 절감 vs 고가용성)을 나타내기 때문입니다. 코드에서 의도가 명확하게 드러나도록 의도적으로 하드코딩했습니다.

---

## 7. State / Backend 분리

각 환경은 동일한 S3 bucket을 사용하되, `key` 경로로 state를 분리합니다.

| 환경 | State Key |
|---|---|
| environments/dev | `deepdive/mission5/dev/terraform.tfstate` |
| environments/prod | `deepdive/mission5/prod/terraform.tfstate` |

Mission 1~4의 state 경로(`deepdive/mission1~4/`)와 완전히 분리되어 있습니다.  
Mission 5를 destroy한 후에도 원본 state는 영향을 받지 않습니다.

```hcl
# environments/dev/main.tf
backend "s3" {
  bucket = "<your-bucket-name>"
  key    = "deepdive/mission5/dev/terraform.tfstate"
  region = "us-east-2"
}

# environments/prod/main.tf
backend "s3" {
  bucket = "<your-bucket-name>"
  key    = "deepdive/mission5/prod/terraform.tfstate"
  region = "us-east-2"
}
```

`.terraform.lock.hcl`은 각 root module 디렉토리(environments/dev, environments/prod)에 생성되며, 프로바이더 버전 재현성을 위해 커밋 대상입니다.
