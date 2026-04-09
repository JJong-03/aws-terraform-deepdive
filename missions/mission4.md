# Mission 4 — Cache

## 목표

고속 읽기가 필요한 데이터를 Redis에 캐시하는 미션이다.
ElastiCache Redis를 Private Subnet에 배치하고,
Multi-AZ, Automatic Failover, AUTH token, TLS, at-rest encryption을 적용한다.

---

## 학습 목표

- ElastiCache Redis Replication Group 개념
- Subnet Group으로 Private Subnet 내 배치
- Multi-AZ + Automatic Failover
- Redis AUTH 토큰 + transit encryption (TLS)
- at-rest encryption
- Parameter Group으로 Redis 설정 튜닝
- Snapshot / Maintenance Window
- terraform_remote_state로 Mission 1 / 2 output 참조

---

## 이전 미션 의존성

Mission 4는 아래를 전제로 한다:
- Mission 1 완료 (`private_subnet_ids`, `sg_redis_id` 참조)
- Mission 2 완료 (`redis_auth_token` 참조)

```hcl
data "terraform_remote_state" "mission1" {
  backend = "s3"
  config = {
    bucket = "<Mission 1과 동일 bucket>"
    key    = "deepdive/mission1/terraform.tfstate"
    region = "us-east-2"
  }
}

data "terraform_remote_state" "mission2" {
  backend = "s3"
  config = {
    bucket = "<Mission 1과 동일 bucket>"
    key    = "deepdive/mission2/terraform.tfstate"
    region = "us-east-2"
  }
}
```

| 참조값 | 출처 | 사용처 |
|---|---|---|
| `private_subnet_ids` | Mission 1 | Subnet Group |
| `sg_redis_id` | Mission 1 | Replication Group security_group_ids |
| `redis_auth_token` | Mission 2 | Replication Group auth_token |

> `redis_auth_token`을 remote_state로 참조하면 코드/tfvars 직접 노출을 줄일 수 있다.
> 단, Mission 4 state에도 저장되므로 state 보안(S3 암호화, 접근 제어)은 별도로 필요하다.

---

## 현재 범위

### ElastiCache Replication Group 사양

| 항목 | 학습 최소 (적용) | 실무 권장 |
|---|---|---|
| `node_type` | `cache.t3.micro` | `cache.r6g.large` |
| `num_cache_clusters` | 2 (primary 1 + replica 1) | 2~3 |
| `snapshot_retention_limit` | 1일 | 7일 |
| `apply_immediately` | true (dev) | false (prod) |

### 확정 사양

| 항목 | 값 |
|---|---|
| `engine` | redis |
| `engine_version` | 7.0 |
| `node_type` | cache.t3.micro |
| `num_cache_clusters` | 2 |
| `automatic_failover_enabled` | true |
| `multi_az_enabled` | true |
| `transit_encryption_enabled` | true |
| `at_rest_encryption_enabled` | true |
| `auth_token` | Mission 2 remote_state 참조 |
| `snapshot_retention_limit` | 1 |
| `snapshot_window` | "03:00-04:00" |
| `maintenance_window` | "sun:05:00-sun:06:00" |
| `apply_immediately` | dev=true, prod=false (locals 계산) |

### AUTH token 주의사항

- `transit_encryption_enabled = true`일 때만 `auth_token` 설정 가능 (AWS 필수 조건)
- 한 번 설정된 auth_token은 변경만 가능하고 제거 불가 (AWS 제약)
- `auth_token` 값은 Mission 4 state 파일에도 저장됨 — state 보안 별도 관리 필요
- 학습용으로는 이대로 진행하되, 실무에서는 state 암호화 + 접근 제한을 엄격히 적용

### Parameter Group

| 항목 | 값 |
|---|---|
| family | redis7 |
| 이름 | `kjw-deepdive-dev-pg-redis` (소문자 기반) |
| 파라미터 | `maxmemory-policy = allkeys-lru` |

> `allkeys-lru`: 메모리 부족 시 LRU 기준 키 삭제. 캐시 용도에 적합.

### Subnet Group + AZ 배치

Mission 1의 `private_subnet_ids` (us-east-2a, us-east-2c)를 Subnet Group에 모두 등록.
`multi_az_enabled = true` + `num_cache_clusters = 2` 조합으로 서로 다른 AZ 배치를 유도.
실제 배치 결과는 apply 후 콘솔의 Nodes 탭에서 확인한다.

---

## ElastiCache 리소스 식별자 네이밍 규칙

ElastiCache 식별자 (replication_group_id, parameter group name, subnet group name)는
**소문자, 숫자, 하이픈만 허용**한다. 대문자 포함 시 apply 실패.

| 구분 | 형식 |
|---|---|
| Name 태그 | `KJW-${project_name}-${environment}-...` |
| ElastiCache 식별자 | `lower("kjw-${project_name}-${environment}")-...` |

---

## SSM Parameter 업데이트

Mission 4 apply 후 Redis endpoint를 신규 SSM 파라미터로 저장:

| 경로 | 값 |
|---|---|
| `/deepdive/dev/redis/host` | Primary endpoint address |
| `/deepdive/dev/redis/reader_host` | Reader endpoint address |

---

## 현재 범위에서 제외

- EC2 (Redis 접속 테스트 클라이언트)
- Cluster Mode (non-cluster 구성으로 진행)
- 모듈화
- CloudWatch 알람 / 대시보드

---

## 기본 디렉토리 구조

```text
terraform-deepdive/
└── mission4-cache/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars
```

### variables.tf

| 변수명 | 기본값 |
|---|---|
| `aws_region` | "us-east-2" |
| `environment` | "dev" |
| `project_name` | "deepdive" |

locals 계산값:
- `name_prefix = "KJW-${var.project_name}-${var.environment}"`
- `id_prefix = lower("kjw-${var.project_name}-${var.environment}")`
- `apply_immediately = var.environment == "prod" ? false : true`

---

## 네이밍 / 태그 규칙 (Mission 1~3와 동일)

| 구분 | 형식 |
|---|---|
| Name 태그 | `KJW-project-environment-...` |
| ElastiCache 식별자 | `kjw-project-environment-...` (소문자) |
| provider default_tags | Owner, Environment, Project |

---

## backend 설정

```hcl
backend "s3" {
  bucket = "<Mission 1과 동일 bucket 이름 수동 입력>"
  key    = "deepdive/mission4/terraform.tfstate"
  region = "us-east-2"
}
```

---

## 예상 resource 수

```
aws_elasticache_parameter_group.main       1
aws_elasticache_subnet_group.main          1
aws_elasticache_replication_group.main     1  (내부 노드 2개: primary + replica)
aws_ssm_parameter.redis_host               1
aws_ssm_parameter.redis_reader_host        1
────────────────────────────────────────────
합계                                        5 resources
data sources                                2 (terraform_remote_state × 2)
```

---

## 예상 산출물 (outputs)

| output 이름 | 설명 |
|---|---|
| `redis_primary_endpoint` | Primary endpoint address |
| `redis_reader_endpoint` | Reader endpoint address |
| `redis_port` | 포트 (6379) |
| `redis_replication_group_id` | Replication Group ID |
| `redis_subnet_group_name` | Subnet Group 이름 |

---

## 완료 체크리스트

- [ ] Replication Group이 available 상태로 생성
- [ ] Primary / Replica가 서로 다른 AZ에 배치 (콘솔 Nodes 탭 확인)
- [ ] Automatic Failover = Enabled
- [ ] transit_encryption_enabled = true
- [ ] at_rest_encryption_enabled = true
- [ ] AUTH 토큰 설정됨
- [ ] SSM Parameter `/deepdive/dev/redis/host` 저장됨
- [ ] Reader Endpoint output 제공
- [ ] (선택) Failover 테스트 완료

---

## 검증 포인트

| 단계 | 확인 사항 |
|---|---|
| `terraform validate` | "Success! The configuration is valid." |
| `terraform plan` | "Plan: 5 to add, 0 to change, 0 to destroy" |
| `terraform apply` | 10~15분 소요 |
| `terraform output` | 5개 output 확인 |
| ElastiCache 콘솔 | Replication Group 상태 = available |
| AZ 배치 확인 | Nodes 탭에서 Primary/Replica가 서로 다른 AZ에 있는지 확인 |
| Failover 활성화 | Automatic failover = Enabled |
| 암호화 확인 | at-rest = Enabled, In-transit = Enabled |
| SSM 확인 | `/deepdive/dev/redis/host`, `/deepdive/dev/redis/reader_host` 생성 |
| **Failover 테스트 (선택)** | `aws elasticache test-failover --replication-group-id <id> --node-group-id 0001 --region us-east-2` |
| Failover 결과 | Primary AZ 변경됨, primary endpoint DNS 주소는 동일하게 유지됨 |
