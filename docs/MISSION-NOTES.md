# Mission Notes

Mission 1~5 단계별 구현 기록입니다.  
각 미션에서 무엇을 만들었고, Terraform 관점에서 무엇을 배웠는지 정리했습니다.

---

## Mission 1 — Foundation

### 목표

후속 미션 전체의 기반이 되는 네트워크 / 보안 / IAM 인프라를 구성한다.  
Mission 1이 완성되어야 Mission 2~4가 네트워크 위에 올라갈 수 있다.

### 핵심 구현 내용

- VPC 1개 (DNS support / hostnames 활성화)
- Public Subnet × 2, Private Subnet × 2 — us-east-2a, us-east-2c
- Internet Gateway, Elastic IP, NAT Gateway (Public Subnet 2a 배치)
- Public Route Table (IGW), Private Route Table (NAT) + Association
- Security Group 3개
  - `app`: HTTP(80), HTTPS(443) 인바운드 허용
  - `redis`: 6379 포트를 app SG에서만 허용 — SG chaining 적용
  - `vpce`: 443 포트를 app SG에서만 허용 — SG chaining 적용
- IAM Role + Policy (SSM Session Manager + CloudWatch Logs 권한) + Instance Profile
- outputs.tf로 후속 미션이 참조할 값 노출

### Terraform 관점에서 배운 점

**`count`로 반복 생성하기**  
Public Subnet 2개를 `count = length(var.public_subnet_cidrs)`로 생성하고,  
`var.az_names[count.index]`로 각 subnet을 다른 AZ에 배치했다.  
인덱스 순서가 AZ 매핑의 기준이 된다는 점을 처음 체득했다.

**Security Group chaining**  
`cidr_blocks` 대신 `security_groups = [aws_security_group.app.id]`로 참조하면  
IP 기반이 아닌 SG 기반 접근 제어가 가능하다.  
redis SG와 vpce SG가 app SG에만 열려 있어, IP 변경에도 규칙이 유지된다.

**outputs.tf의 역할**  
Terraform에서 state 경계를 넘어 값을 전달하려면 output이 필요하다.  
Mission 1의 `vpc_id`, `private_subnet_ids`, `sg_redis_id`가 Mission 4에서 `terraform_remote_state`로 참조된다는 것을 염두에 두고 output을 설계했다.

### 다음 미션으로의 연결

Mission 1의 output(`private_subnet_ids`, `sg_redis_id`)은 Mission 4(ElastiCache)에서 직접 참조된다.  
Mission 2~3은 VPC 외부 서비스(Secrets Manager, SNS/SQS)라 Mission 1에 직접 의존하지 않는다.

---

## Mission 2 — Secrets

### 목표

애플리케이션 설정값과 민감한 자격증명을 안전하게 관리할 수 있도록  
SSM Parameter Store와 Secrets Manager를 구성한다.

### 핵심 구현 내용

- `random_password`로 DB 비밀번호(20자), Redis AUTH token(32자) 자동 생성
  - DB: 특수문자 허용 (`!#$%&*()-_=+[]<>:?` — `@`, `/`, `"` 제외)
  - Redis: 특수문자 제외 (ElastiCache AUTH token 공백/따옴표 미지원 제약)
- SSM Parameter Store: 앱 설정 5개 (`app/port`, `app/log_level`, `db/port`, `db/name`, `redis/port`)
- Secrets Manager: DB credentials (JSON), Redis AUTH token — 각각 별도 시크릿으로 분리
- `locals`에서 `recovery_window = var.environment == "prod" ? 30 : 7` 자동 계산
- `redis_auth_token` output에 `sensitive = true` 적용

### Terraform 관점에서 배운 점

**SSM Parameter Store vs Secrets Manager 역할 분리**  
설정값(포트, 로그 레벨)은 SSM Parameter Store(String 타입),  
자격증명(비밀번호, 토큰)은 Secrets Manager로 분리했다.  
SecureString은 Secrets Manager와 역할이 겹쳐 이 미션에서는 제외했다.

**`for_each`로 SSM 파라미터 일괄 생성**  
`locals`에 `map` 형태로 파라미터를 정의하고 `for_each = local.ssm_parameters`로 생성했다.  
항목 추가 시 map에 키-값 하나만 추가하면 되는 구조다.

**`sensitive = true`의 의미**  
output에 `sensitive = true`를 붙이면 `terraform output` 출력에서 마스킹된다.  
단, state 파일에는 평문으로 저장되므로 S3 bucket 암호화는 별도로 필요하다.

**`locals`를 통한 환경별 자동 계산**  
`var.environment`만으로 `recovery_window`를 자동 결정했다.  
tfvars에 별도 값을 입력하지 않아도 환경별로 다르게 동작하는 패턴을 처음 사용했다.

### 다음 미션으로의 연결

Mission 2의 `redis_auth_token` output이 Mission 4(ElastiCache)에서  
`terraform_remote_state`로 참조된다. Mission 5에서는 동일한 값을 `module.secrets.redis_auth_token`으로 직접 전달한다.

---

## Mission 3 — Messaging

### 목표

SNS fan-out + SQS + DLQ 기반 비동기 메시징 파이프라인을 구성한다.

### 핵심 구현 내용

- SNS Topic (Standard) 1개
- SQS 메인 큐 2개 (`order`, `notification`) + DLQ 2개 — `for_each` 기반
- `aws_sqs_queue_redrive_allow_policy`로 DLQ별 수신 소스를 자신의 메인 큐 ARN으로 제한
- `data "aws_iam_policy_document"` + `aws_sqs_queue_policy`로 SNS → SQS 전송 허용
  - `aws:SourceArn` 조건으로 지정된 SNS topic에서만 수신
- `aws_sns_topic_subscription`: `depends_on = [aws_sqs_queue_policy.main]`으로 레이스 컨디션 방지

**SNS fan-out 구조:**

```
SNS Topic (events)
  ├── SQS: order        ←→ DLQ: order-dlq
  └── SQS: notification ←→ DLQ: notification-dlq
```

### Terraform 관점에서 배운 점

**`for_each`를 `map`으로 구성하는 이유**  
`count`는 인덱스 기반이라 중간 항목을 삭제하면 그 뒤 리소스를 재생성한다.  
`for_each`는 키 기반이라 `order` 큐를 삭제해도 `notification` 큐에 영향이 없다.  
큐처럼 식별자가 고유한 리소스는 `for_each`가 적합하다.

**`depends_on`을 정말 필요한 곳에만 쓰기**  
queue policy가 생성되기 전에 SNS subscription이 먼저 만들어지면,  
SNS 확인 메시지가 거부되어 subscription이 Pending 상태로 남는다.  
이 경우처럼 암묵적 의존성으로 해결되지 않을 때만 `depends_on`을 사용한다.

**`data "aws_iam_policy_document"`의 역할**  
JSON을 직접 작성하지 않고 HCL 블록으로 IAM policy를 정의한다.  
`for_each`와 함께 사용해 큐마다 독립적인 policy document를 생성했다.

**`raw_message_delivery = false` 선택 이유**  
SNS envelope JSON 형태로 전달되어 MessageId, TopicArn 등 메타데이터가 포함된다.  
학습 환경에서는 메시지 구조를 직접 확인하기 좋다.  
프로덕션에서 body만 처리하는 컨슈머라면 `true`로 전환한다.

### 다음 미션으로의 연결

Mission 3는 VPC 외부 서비스(SNS/SQS)라 Mission 1/2 output을 직접 참조하지 않는다.  
Mission 5에서는 `queues` 변수를 `map(object)` 타입으로 외부에서 주입받는 구조로 바뀌어,  
환경별 `message_retention_seconds` 차이를 모듈 밖에서 제어할 수 있게 된다.

---

## Mission 4 — Cache

### 목표

ElastiCache Redis를 Private Subnet에 Multi-AZ 구성으로 배포하고,  
AUTH token + TLS + at-rest encryption 보안 설정을 적용한다.

### 핵심 구현 내용

- `terraform_remote_state`로 Mission 1(`private_subnet_ids`, `sg_redis_id`)과 Mission 2(`redis_auth_token`) 참조
- ElastiCache Parameter Group (`maxmemory-policy = allkeys-lru`, `family = redis7`)
- ElastiCache Subnet Group — private subnet 2개(2a, 2c) 등록
- ElastiCache Replication Group
  - `num_cache_clusters = 2` (primary + replica)
  - `automatic_failover_enabled = true`, `multi_az_enabled = true`
  - `transit_encryption_enabled = true`, `at_rest_encryption_enabled = true`
  - `auth_token` = Mission 2 remote state 참조
- apply 완료 후 Redis endpoint를 SSM Parameter Store에 자동 저장
- `id_prefix = lower("kjw-...")` — ElastiCache 식별자 소문자 처리

### Terraform 관점에서 배운 점

**`terraform_remote_state`의 역할과 한계**  
다른 state의 output을 읽어오는 방법이다.  
Mission 1(네트워크)과 Mission 4(캐시)를 별도 state로 관리하면서 값을 공유할 수 있었다.  
단, 참조 대상 state가 먼저 apply되어 있어야 하고, state 간 강결합이 생기는 단점이 있다.  
Mission 5에서 이 구조를 모듈 체이닝으로 대체한다.

**ElastiCache 식별자 네이밍 규칙**  
`replication_group_id`, parameter group name, subnet group name은 소문자, 숫자, 하이픈만 허용한다.  
대문자가 포함되면 apply 단계에서 실패한다.  
`locals { id_prefix = lower("kjw-${var.project_name}-${var.environment}") }`로 분리해서 처리했다.

**AUTH token 제약사항**  
`auth_token`은 `transit_encryption_enabled = true`일 때만 설정 가능하다.  
한 번 설정한 이후 제거는 불가능하고 변경만 가능하다. apply 전에 반드시 확인해야 한다.

**`apply_immediately`의 의미**  
`true`면 설정 변경이 즉시 반영되어 잠깐 서비스 중단이 발생할 수 있다.  
`false`면 다음 maintenance window까지 대기한다.  
dev는 `true`, prod는 `false`가 적절하다.

### 다음 미션으로의 연결

Mission 4의 `terraform_remote_state` 체이닝 구조가 Mission 5에서 모듈 체이닝으로 대체된다.  
Mission 5에서는 `module.networking.private_subnet_ids`와 `module.secrets.redis_auth_token`을  
같은 root module에서 직접 cache 모듈에 주입한다.

---

## Mission 5 — Modularization

### 목표

Mission 1~4의 flat 구조를 재사용 가능한 모듈로 리팩토링하고,  
`environments/dev`와 `environments/prod`로 환경을 분리한다.

### 핵심 구현 내용

- `modules/` 4개: networking, secrets, messaging, cache (각 `main.tf / variables.tf / outputs.tf`)
- `environments/dev/`, `environments/prod/` 각 4파일 구성
- `single_nat_gateway` 변수로 dev(NAT 1개) / prod(NAT 2개) 리소스 수 제어
- `queues` 변수를 `map(object)` 타입으로 설계 — `message_retention_seconds`로 dev/prod 차이 주입
- `recovery_window`는 secrets 모듈 내 `locals`에서 자동 계산 — 외부 변수 미노출
- state key를 `deepdive/mission5/dev/`, `deepdive/mission5/prod/`로 분리

### Directory 방식 환경 분리를 선택한 이유

Terraform Workspace 방식과 비교했을 때 Directory 방식을 선택했다.

| 항목 | Workspace | Directory |
|---|---|---|
| 환경 구분 방법 | `terraform workspace select dev` | 디렉토리 이동 (`cd environments/dev`) |
| 실수 위험 | workspace 이름 착각으로 prod에 잘못 apply 가능 | 디렉토리 이동으로 명시적 확인 |
| lifecycle 블록 | 동적 변수 제어 불가 (static expression만 허용) | 환경별 파일로 자유롭게 설정 가능 |
| 가시성 | 추상적 | 파일 시스템이 곧 환경 구조 |

Terraform `lifecycle` 블록은 동적 변수를 받을 수 없다. 환경별로 `prevent_destroy`를 켜고 끄는 것처럼 환경별 커스터마이징이 필요한 경우 Directory 방식이 훨씬 명확하다.

### Module Chaining

Mission 1~4에서는 `terraform_remote_state`로 다른 state의 output을 참조했다.  
Mission 5는 4개 모듈이 하나의 root module 아래 있으므로 output을 직접 전달할 수 있다.

```hcl
module "cache" {
  # networking output → cache input
  private_subnet_ids = module.networking.private_subnet_ids
  sg_redis_id        = module.networking.sg_redis_id

  # secrets output → cache input
  redis_auth_token   = module.secrets.redis_auth_token
}
```

`terraform_remote_state`를 제거한 효과:
- 단일 `terraform apply`로 전체 인프라 관리
- 의존 모듈의 output이 바뀌면 자동 전파
- state 간 의존성 제거로 관리 포인트 감소

### Dev / Prod 차이 설계

환경마다 다른 값이 필요한 부분을 세 가지 방식으로 처리했다.

**1. 변수로 주입 (environments에서 module로)**  
캐시 node_type, clusters 수, apply_immediately, snapshot 보관 기간처럼  
환경마다 명확히 다른 값은 environment의 `variables.tf` default값으로 분리했다.

**2. module 내 locals 자동 계산**  
`recovery_window`처럼 environment 값 하나로 결정할 수 있는 것은  
모듈 내부 `locals`에서 계산해 외부 변수를 노출하지 않았다.

**3. main.tf 하드코딩**  
`single_nat_gateway`는 dev main.tf에서 `true`, prod main.tf에서 `false`로 고정했다.  
이 값은 환경의 고유한 성격(비용 절감 vs 고가용성)을 나타내므로,  
코드에서 의도가 명확히 드러나도록 변수로 열지 않았다.

### Terraform 관점에서 배운 점

**모듈의 입력/출력 인터페이스 설계**  
모듈은 `variables.tf`(입력)와 `outputs.tf`(출력)로 외부와 계약을 정의한다.  
내부 구현이 바뀌어도 인터페이스가 유지되면 호출부는 영향을 받지 않는다.

**`count` vs `for_each` 선택 기준**  
순서와 개수가 중요한 리소스(Subnet, EIP, NAT, Route Table)는 `count`,  
키로 식별하는 리소스(SQS Queue, SSM Parameter)는 `for_each`를 사용했다.  
중간 항목 삭제 시 `count`는 이후 항목을 재생성하지만 `for_each`는 해당 항목만 처리한다.

**루트 모듈 output re-expose**  
`terraform output`은 루트 모듈의 output만 표시한다.  
모듈 내부 output은 자동으로 노출되지 않으므로,  
`environments/dev/outputs.tf`에서 필요한 값을 명시적으로 re-expose해야 한다.

**`lifecycle { prevent_destroy }`의 한계**  
`lifecycle` 블록은 동적 변수를 받을 수 없다.  
module 호출부에서 module 내부 리소스의 lifecycle을 직접 제어하는 것도 불가능하다.  
prod 환경에서 필요하다면 모듈 내부 리소스에 직접 추가해야 한다.  
이번 프로젝트에서는 학습 목적으로 개념만 다루고 코드에 구현하지 않았다.

---

## 전체 흐름 요약

| Mission | 핵심 내용 | Terraform 포인트 |
|---|---|---|
| 1 — Foundation | VPC, Subnet, IGW, NAT, SG, IAM | `count`, SG chaining, outputs 설계 |
| 2 — Secrets | SSM, Secrets Manager, random_password | `for_each` map, `sensitive`, locals 자동 계산 |
| 3 — Messaging | SNS, SQS, DLQ, Queue Policy | `for_each` map(object), `depends_on` 최소화 |
| 4 — Cache | ElastiCache Multi-AZ, AUTH, TLS | `terraform_remote_state`, 소문자 식별자 |
| 5 — Modular | modules + environments, dev/prod 분리 | 모듈 인터페이스, 체이닝, Directory 방식 환경 분리 |
