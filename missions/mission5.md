# Mission 5 — Modularization

## 목표

Mission 1~4에서 flat 구조로 작성한 Terraform 코드를 재사용 가능한 modules로 리팩토링하고,
`environments/dev`, `environments/prod` 디렉토리 구조로 환경을 분리한다.

---

## 학습 목표

- Terraform 모듈 설계 (입력/출력 인터페이스 정의)
- module output → module input 체이닝
- Directory 방식 환경 분리 (vs Workspace 방식)
- `single_nat_gateway` 변수로 dev/prod 리소스 수 제어
- `count` vs `for_each` 선택 기준
- `lifecycle prevent_destroy` 개념과 Terraform 제약
- backend state key 환경별 분리

---

## Mission 5의 위치 — 기존 mission1~4와의 관계

Mission 5는 mission1~4를 **참고 원본**으로 삼아 modules + environments 구조로 재구성하는 단계다.

```
mission1-foundation/   ← 원본 참고 (건드리지 않음)
mission2-secrets/      ← 원본 참고 (건드리지 않음)
mission3-messaging/    ← 원본 참고 (건드리지 않음)
mission4-cache/        ← 원본 참고 (건드리지 않음)
mission5-modular/      ← 신규 구성 (modules + environments)
```

**기존 apply 상태 처리:**
mission1~4가 이미 apply된 상태에서 mission5를 배포하면 중복 리소스 생성 + 비용 증가 + 서비스 한도 충돌 위험이 있다.

권장 순서 (코드 validate 성공 확인 후 destroy):
```bash
# 역순으로 destroy (의존성 역방향)
cd mission4-cache/      && terraform destroy
cd mission3-messaging/  && terraform destroy
cd mission2-secrets/    && terraform destroy
cd mission1-foundation/ && terraform destroy
```

> **import/migration은 권장하지 않는다.**
> 학습 환경에서는 destroy → fresh deploy가 가장 명확하고 오류가 없다.
> destroy 타이밍: 코드 작성 → validate 성공 → destroy → apply 순으로 진행해야
> validate 실패 시 인프라 공백 상태가 되는 위험을 피할 수 있다.

---

## Workspace vs Directory 방식 비교

| 항목 | Workspace 방식 | **Directory 방식 (권장)** |
|---|---|---|
| 구조 | 단일 코드베이스, workspace로 환경 분리 | environments/dev, environments/prod 별도 디렉토리 |
| 가시성 | workspace 이름으로만 구분 — 직관적이지 않음 | 파일 시스템이 곧 환경 구조 |
| 실수 위험 | workspace 착각으로 prod에 잘못 apply 가능 | 디렉토리 이동으로 명시적 확인 |
| 학습 적합성 | 추상적 | 직관적, lifecycle 등 환경별 커스터마이징 용이 |

> **권장: Directory 방식**
> Terraform `lifecycle` 블록은 동적 변수 제어가 불가능하다 (static expression만 허용).
> 이 제약으로 인해 환경별 커스터마이징이 필요할 때 Directory 방식이 훨씬 명확하다.

---

## 디렉토리 구조

```
terraform-deepdive/
└── mission5-modular/
    ├── modules/
    │   ├── networking/
    │   │   ├── main.tf
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   ├── secrets/
    │   │   ├── main.tf
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   ├── messaging/
    │   │   ├── main.tf
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   └── cache/
    │       ├── main.tf
    │       ├── variables.tf
    │       └── outputs.tf
    └── environments/
        ├── dev/
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   └── terraform.tfvars
        └── prod/
            ├── main.tf
            ├── variables.tf
            ├── outputs.tf
            └── terraform.tfvars
```

---

## 모듈별 책임 분리

### modules/networking

Mission 1 범위 (VPC, Subnet, IGW, EIP, NAT, Route Table, SG, IAM)

IAM(EC2 Instance Profile)을 networking에 포함한다.
EC2 Instance Profile은 네트워크 인프라와 밀접하고, 모듈 수를 최소화(4개)하는 것이 학습에 적합하다.

**입력 변수:**

| 변수명 | 설명 |
|---|---|
| `environment`, `project_name` | 네이밍 |
| `vpc_cidr` | VPC CIDR |
| `az_names` | 사용 AZ 목록 |
| `public_subnet_cidrs` | Public Subnet CIDRs (az_names와 동일 길이, 동일 순서) |
| `private_subnet_cidrs` | Private Subnet CIDRs (az_names와 동일 길이, 동일 순서) |
| `single_nat_gateway` | true=NAT 1개(dev), false=AZ당 1개(prod) |

**입력 전제 조건 (NAT/Route Table AZ 매핑 안전성):**
`public_subnet_cidrs[0]`은 `az_names[0]` AZ에, `private_subnet_cidrs[0]`도 `az_names[0]` AZ에 배치되는 구조다.
순서가 틀리면 prod에서 NAT Gateway와 Route Table의 AZ 매핑이 어긋난다.
variables.tf에 validation 블록으로 길이 일치를 강제한다.

**outputs:**
`vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `sg_app_id`, `sg_redis_id`, `sg_vpce_id`, `app_role_arn`, `app_instance_profile_name`, `iam_instance_profile_arn`

---

### modules/secrets

Mission 2 범위 (SSM Parameters + Secrets Manager + random_password)

**입력 변수:** `environment`, `project_name`

**outputs:** `ssm_parameter_prefix`, `db_credentials_secret_arn`, `db_credentials_secret_name`, `redis_auth_secret_arn`, `redis_auth_token` (sensitive=true)

`recovery_window`은 `var.environment == "prod" ? 30 : 7` 로 모듈 내 locals에서 자동 계산한다. 별도 변수 노출 없음.

---

### modules/messaging

Mission 3 범위 (SNS + SQS + DLQ + 정책 + 구독)

**입력 변수:** `environment`, `project_name`, `queues` (map(object))

**outputs:** `sns_topic_arn`, `sqs_queue_urls`, `sqs_queue_arns`, `dlq_queue_arns`

`message_retention_seconds`는 queues 변수의 각 큐 오브젝트 내 필드로 dev/prod 차이를 주입한다.

---

### modules/cache

Mission 4 범위 (ElastiCache Replication Group + Parameter Group + Subnet Group + SSM endpoint 저장)

**입력 변수:**

| 변수명 | 설명 |
|---|---|
| `environment`, `project_name` | 네이밍 |
| `private_subnet_ids` | module.networking output에서 주입 |
| `sg_redis_id` | module.networking output에서 주입 |
| `redis_auth_token` | module.secrets output에서 주입 |
| `node_type` | ElastiCache 노드 타입 |
| `num_cache_clusters` | 노드 수 |
| `apply_immediately` | 즉시 적용 여부 |
| `snapshot_retention_limit` | 스냅샷 보관 기간 |

**outputs:** `redis_primary_endpoint`, `redis_reader_endpoint`, `redis_port`, `redis_replication_group_id`, `redis_subnet_group_name`

---

## NAT Gateway — Dev / Prod 리소스 수준 구현 차이

`single_nat_gateway` 변수 하나로 EIP/NAT Gateway/Private Route Table 개수가 달라진다.

### Dev (single_nat_gateway = true)
```
EIP             1개
NAT Gateway     1개 (public subnet 2a에 배치)
Private RT      1개 (0.0.0.0/0 → 단일 NAT)
RT Association  2개 (private 2a, 2c 모두 같은 RT 참조)
```

### Prod (single_nat_gateway = false)
```
EIP             2개 (AZ당 1개)
NAT Gateway     2개 (public 2a + public 2c)
Private RT      2개 (각 AZ별 RT, 자신의 AZ NAT 참조)
RT Association  2개 (각 private subnet → 같은 AZ RT)
```

**구현 패턴 (networking 모듈 내):**

```hcl
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

networking 모듈 리소스 수 차이:
- Dev: EIP 1 + NAT 1 + Private RT 1 = 3개
- Prod: EIP 2 + NAT 2 + Private RT 2 = 6개 (차이 +3)

---

## Module Output → Module Input 체이닝

**terraform_remote_state가 아닌 같은 root module 안에서 직접 체이닝한다.**

이유: 단일 apply로 전체 인프라 관리, state 간 의존성 없음, 변경 자동 전파.

```hcl
# environments/dev/main.tf

module "networking" {
  source               = "../../modules/networking"
  environment          = var.environment
  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  az_names             = var.az_names
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = true   # dev 고정
}

module "secrets" {
  source       = "../../modules/secrets"
  environment  = var.environment
  project_name = var.project_name
}

module "messaging" {
  source       = "../../modules/messaging"
  environment  = var.environment
  project_name = var.project_name
  queues       = var.queues
}

module "cache" {
  source       = "../../modules/cache"
  environment  = var.environment
  project_name = var.project_name

  # Output → Input 체이닝
  private_subnet_ids = module.networking.private_subnet_ids
  sg_redis_id        = module.networking.sg_redis_id
  redis_auth_token   = module.secrets.redis_auth_token

  node_type                = var.cache_node_type
  num_cache_clusters       = var.cache_num_clusters
  apply_immediately        = var.cache_apply_immediately
  snapshot_retention_limit = var.cache_snapshot_retention
}
```

---

## environments/dev · prod — outputs.tf 책임

`terraform output`은 **루트 모듈의 output만** 표시한다.
모듈 내부 output은 자동으로 노출되지 않으므로, 각 environment의 `outputs.tf`에서 필요한 값을 명시적으로 re-expose해야 한다.

```hcl
# environments/dev/outputs.tf (environments/prod/outputs.tf도 동일 구조)

output "vpc_id"                    { value = module.networking.vpc_id }
output "private_subnet_ids"        { value = module.networking.private_subnet_ids }
output "redis_primary_endpoint"    { value = module.cache.redis_primary_endpoint }
output "redis_reader_endpoint"     { value = module.cache.redis_reader_endpoint }
output "redis_port"                { value = module.cache.redis_port }
output "sns_topic_arn"             { value = module.messaging.sns_topic_arn }
output "sqs_queue_urls"            { value = module.messaging.sqs_queue_urls }
output "db_credentials_secret_arn" { value = module.secrets.db_credentials_secret_arn }
output "redis_auth_token"          { value = module.secrets.redis_auth_token; sensitive = true }
```

노출 기준: downstream 소비(다른 시스템 참조), 운영 확인(엔드포인트, ARN), 디버깅에 필요한 값.

---

## Dev / Prod 환경 차이

| 항목 | Dev | Prod |
|---|---|---|
| **networking** | | |
| `vpc_cidr` | 10.0.0.0/16 | 10.1.0.0/16 |
| `single_nat_gateway` | true (1개) | false (AZ당 1개) |
| EIP / NAT 수 | 각 1개 | 각 2개 |
| **secrets** | | |
| `recovery_window` | 7일 (locals 자동 계산) | 30일 (locals 자동 계산) |
| **messaging** | | |
| `message_retention_seconds` | 345600 (4일) | 604800 (7일) |
| **cache** | | |
| `node_type` | cache.t3.micro | cache.r6g.large |
| `num_cache_clusters` | 2 | 3 |
| `apply_immediately` | true | false |
| `snapshot_retention_limit` | 1 | 7 |

**cache dev=2 clusters 유지 이유:**
`num_cache_clusters = 1`이면 `automatic_failover_enabled = false` 필수이고 Multi-AZ도 불가하다.
dev에서도 HA 구조(primary + replica) 학습이 목표이므로 2 clusters를 유지한다.

---

## count vs for_each 선택 기준

| 리소스 | 방식 | 이유 |
|---|---|---|
| Public/Private Subnet | `count` | 순서 기반, index로 AZ 매핑 |
| EIP / NAT Gateway | `count` | single_nat_gateway 조건부 개수 |
| Route Table (private) | `count` | NAT 개수와 1:1 대응 |
| Route Table Association | `count` | subnet과 1:1 대응 |
| SQS Queue / DLQ | `for_each` | 키로 참조, 중간 삭제 시 나머지 영향 없음 |
| SSM Parameters (앱 설정) | `for_each` | map 구조, 키-값 명확 |
| SNS Subscription | `for_each` | queue 맵과 동일 키 |
| Secrets Manager (db, redis) | 개별 리소스 | 2개뿐, for_each 오버엔지니어링 |

---

## lifecycle prevent_destroy — 개념과 Terraform 제약

**이번 Mission 5 코드에는 실제 구현하지 않는다.**

이유:
1. Terraform `lifecycle` 블록은 동적 변수 제어 불가 (static expression만 허용)
2. module 호출부에서 module 내부 리소스의 lifecycle을 직접 제어할 수 없다
3. 학습 범위에서 구조가 과도하게 복잡해진다

**실무에서는 prod 리소스에 직접 추가:**
```hcl
resource "aws_vpc" "main" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```

적용 대상 (prod): VPC, ElastiCache Replication Group, Secrets Manager secrets
이 세 리소스는 파괴 시 전체 서비스 중단 또는 데이터 손실 위험이 있다.

---

## backend / state 전략

| 환경 | key |
|---|---|
| environments/dev | `deepdive/mission5/dev/terraform.tfstate` |
| environments/prod | `deepdive/mission5/prod/terraform.tfstate` |

Mission 1~4 state와 경로 분리. Mission 5 destroy 후에도 원본 state 보존.

---

## Prod 환경 배포 범위

| 환경 | 권장 |
|---|---|
| Dev | `terraform apply` 필수 |
| Prod | `terraform plan` 필수, `terraform apply` 선택 |

**이유:**
prod는 `cache.r6g.large` + NAT 2개를 사용하므로 apply 시 시간당 비용이 크게 발생한다.
`terraform plan` 출력만으로도 Dev/Prod 차이(node_type, NAT 개수, retention 등)를 코드 수준에서 확인할 수 있다.

prod apply가 필요하다면 tfvars에서 `cache_node_type = "cache.t3.micro"`로 임시 변경 후 진행하고 완료 후 즉시 destroy한다.

---

## 예상 resource 수

**environments/dev:**
```
module.networking    ~20 resources (NAT 1개 기준)
module.secrets       ~11 resources
module.messaging     ~11 resources
module.cache          ~5 resources
──────────────────────────────────
합계                 ~47 resources
```

**environments/prod (plan 기준):**
```
module.networking    ~23 resources (NAT 2개 기준, +3)
module.secrets       ~11 resources
module.messaging     ~11 resources (retention 값만 다름)
module.cache          ~5 resources (node_type 다름)
──────────────────────────────────
합계                 ~50 resources
```

---

## 실행 순서

```bash
# Step 1: 코드 작성
#   mission5-modular/modules/ → mission5-modular/environments/

# Step 2: 코드 검증 (destroy 전에 먼저 확인)
cd mission5-modular/environments/dev/
terraform init && terraform validate

cd mission5-modular/environments/prod/
terraform init && terraform validate

# Step 3: 기존 mission1~4 destroy (validate 성공 후, 역순으로)
cd mission4-cache/      && terraform destroy
cd mission3-messaging/  && terraform destroy
cd mission2-secrets/    && terraform destroy
cd mission1-foundation/ && terraform destroy

# Step 4: Dev 배포
cd mission5-modular/environments/dev/
terraform plan    # ~47 to add 확인
terraform apply

# Step 5: Prod 검증
cd mission5-modular/environments/prod/
terraform plan    # Dev와의 차이 확인 (NAT 수, node_type 등)
# terraform apply  ← 비용 주의

# Step 6: 정리 (실습 후)
cd mission5-modular/environments/dev/
terraform destroy
```

---

## 검증 포인트

| 단계 | 확인 사항 |
|---|---|
| `terraform validate` | 모듈 경로, 변수 타입 오류 없음 |
| Dev plan | ~47 to add, 0 to change, 0 to destroy |
| Dev apply | 성공 |
| `terraform output` | 루트 모듈 output (re-exposed) 확인 |
| 체이닝 확인 | module.cache가 module.networking/secrets output 정상 수신 |
| module.networking | VPC, Subnet, SG, IAM 생성 |
| module.secrets | SSM params, Secrets Manager 확인 |
| module.messaging | SNS, SQS Confirmed 상태 |
| module.cache | ElastiCache available, AZ 분산 |
| **Prod plan** | node_type=r6g.large, NAT 2개, retention 차이 확인 |

---

## 완료 체크리스트

- [ ] modules/networking → dev, prod 공통 모듈로 동작 확인
- [ ] modules/secrets → dev, prod 공통 모듈로 동작 확인
- [ ] modules/messaging → queues 변수로 dev/prod 큐 설정 차이 반영
- [ ] modules/cache → node_type 등 변수로 dev/prod 차이 반영
- [ ] module output → module input 체이닝 (networking → cache, secrets → cache)
- [ ] environments/dev · prod outputs.tf에서 module output re-expose 확인
- [ ] environments/dev terraform apply 성공
- [ ] environments/prod terraform plan 성공 (diff 확인)
- [ ] Dev/Prod NAT 개수 차이 plan 출력에서 확인
- [ ] Dev/Prod cache node_type 차이 plan 출력에서 확인
- [ ] prevent_destroy 개념 이해 (코드 미구현 이유 포함)
