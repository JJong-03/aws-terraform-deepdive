# Troubleshooting

프로젝트 진행 중 실제로 겪은 문제와 해결 방법을 정리했습니다.

---

## 목차

1. [Secrets Manager — 동일 이름 시크릿 재생성 실패](#1-secrets-manager--동일-이름-시크릿-재생성-실패)
2. [ElastiCache — 식별자에 대문자 포함 시 apply 실패](#2-elasticache--식별자에-대문자-포함-시-apply-실패)
3. [SNS Subscription — Pending 상태로 유지됨](#3-sns-subscription--pending-상태로-유지됨)
4. [terraform_remote_state — output 참조 혼동](#4-terraform_remote_state--output-참조-혼동)
5. [prod 환경 — apply 없이 plan만 확인한 이유](#5-prod-환경--apply-없이-plan만-확인한-이유)
6. [GitHub 공개 전 — 민감 파일 노출 주의](#6-github-공개-전--민감-파일-노출-주의)

---

## 1. Secrets Manager — 동일 이름 시크릿 재생성 실패

### 문제 상황

`terraform destroy` 후 동일한 시크릿 이름으로 `terraform apply`를 다시 실행하면 아래 오류가 발생한다.

```
Error: creating Secrets Manager Secret: InvalidRequestException:
You can't create this secret because a secret with this name is already scheduled for deletion.
```

### 원인

Secrets Manager는 시크릿을 즉시 삭제하지 않는다.  
`recovery_window_in_days` 기간 동안 "scheduled for deletion" 상태로 유지되며,  
이 기간 중에는 동일한 이름으로 새 시크릿을 생성할 수 없다.

이 프로젝트에서는 `recovery_window_in_days = 7` (dev) / `30` (prod)을 설정했다.

### 해결 방법

**방법 1 (권장): restore-secret → terraform import → terraform apply**

삭제 예약 상태의 시크릿을 복구한 뒤 Terraform state에 import해서 그대로 재사용한다.  
기존 시크릿 ARN이 유지되므로 참조 경로를 바꿀 필요가 없다.

```bash
# Step 1: 삭제 예약 상태인 시크릿 복구
aws secretsmanager restore-secret \
  --secret-id deepdive/dev/db-credentials \
  --region us-east-2

aws secretsmanager restore-secret \
  --secret-id deepdive/dev/redis-auth \
  --region us-east-2
```

```bash
# Step 2: 복구된 시크릿을 Terraform state에 import
# (terraform이 리소스를 새로 만들려 하지 않도록 기존 리소스를 state에 등록)
# mission5-modular 기준 — secrets 모듈 주소를 포함한 전체 경로 사용
terraform import module.secrets.aws_secretsmanager_secret.db deepdive/dev/db-credentials
terraform import module.secrets.aws_secretsmanager_secret.redis deepdive/dev/redis-auth
```

```bash
# Step 3: import 이후 정상 apply
terraform apply
```

import 후 `terraform plan`을 먼저 실행해 변경 사항이 없는지(`0 to add, 0 to change`) 확인하고 apply하는 것이 안전하다.

**방법 2 (대안): 강제 삭제 후 재생성**

복구가 어렵거나 시크릿을 새로 만들어야 하는 경우, 강제 삭제 후 apply를 재실행한다.  
단, 이 방법은 복구 불가능하므로 신중하게 사용한다.

```bash
# 시크릿 이름 확인
aws secretsmanager list-secrets --region us-east-2 \
  --query "SecretList[?contains(Name, 'deepdive')].{Name:Name, DeletedDate:DeletedDate}"

# 즉시 삭제 (복구 불가)
aws secretsmanager delete-secret \
  --secret-id deepdive/dev/db-credentials \
  --force-delete-without-recovery \
  --region us-east-2

aws secretsmanager delete-secret \
  --secret-id deepdive/dev/redis-auth \
  --force-delete-without-recovery \
  --region us-east-2
```

강제 삭제 후 `terraform apply`를 재실행한다.

### 다시 막지 않기 위한 체크 포인트

- `terraform destroy` 후 바로 재생성할 계획이라면 `restore-secret → import` 흐름을 먼저 시도한다.
- 학습 환경에서는 destroy 후 재생성하는 경우가 많으므로 dev는 `recovery_window_in_days`를 낮게 설정해 두면 편하다.
- 강제 삭제(`force-delete-without-recovery`)는 복구가 불가능하므로 마지막 수단으로 사용한다.

---

## 2. ElastiCache — 식별자에 대문자 포함 시 apply 실패

### 문제 상황

`terraform apply` 실행 시 ElastiCache 관련 리소스에서 아래 오류가 발생한다.

```
Error: creating ElastiCache Replication Group: InvalidParameterValue:
The parameter ReplicationGroupId must consist of lowercase alphanumeric characters or hyphens.
```

### 원인

ElastiCache의 `replication_group_id`, parameter group name, subnet group name은  
**소문자, 숫자, 하이픈**만 허용한다.  
다른 리소스에서 사용하는 `KJW-deepdive-dev` 형태의 name prefix를 그대로 사용하면 대문자가 포함되어 실패한다.

### 해결 방법

ElastiCache 식별자 전용 prefix를 `locals`에서 `lower()`로 별도 정의한다.

```hcl
locals {
  name_prefix = "KJW-${var.project_name}-${var.environment}"   # Name 태그용
  id_prefix   = lower("kjw-${var.project_name}-${var.environment}")  # ElastiCache 식별자용
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${local.id_prefix}-redis"   # kjw-deepdive-dev-redis
  # ...
}
```

Name 태그는 `local.name_prefix`(대문자 포함), ElastiCache 식별자는 `local.id_prefix`(소문자 전용)로 분리해서 사용한다.

### 다시 막지 않기 위한 체크 포인트

- `replication_group_id`, `parameter_group_name`, `subnet_group_name` 설정 시 반드시 소문자 확인
- `lower()` 함수를 locals에서 한 번만 처리해두면 이후 참조에서 실수가 없다

---

## 3. SNS Subscription — Pending 상태로 유지됨

### 문제 상황

`terraform apply` 완료 후 AWS 콘솔에서 SNS Subscription 상태를 확인하면  
`Confirmed`가 아닌 `PendingConfirmation` 상태로 남아 있다.

### 원인

SNS가 SQS 큐에 구독 확인 메시지를 보낼 때, SQS queue policy가 아직 생성되지 않았으면  
큐가 메시지를 거부한다. 이 상태에서 subscription이 먼저 생성되면 확인 메시지가 누락되고  
Pending 상태로 남는다.

Terraform은 리소스 간 참조가 없으면 의존성을 자동으로 파악하지 못한다.  
`aws_sns_topic_subscription`은 `aws_sqs_queue_policy`의 ARN을 직접 참조하지 않으므로  
기본적으로 병렬 생성이 시도된다.

### 해결 방법

`aws_sns_topic_subscription`에 `depends_on`을 명시해 queue policy 생성 완료 후 subscription이 생성되도록 순서를 보장한다.

```hcl
resource "aws_sns_topic_subscription" "main" {
  for_each = var.queues

  topic_arn = aws_sns_topic.main.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.main[each.key].arn

  depends_on = [aws_sqs_queue_policy.main]   # 순서 보장
}
```

이미 Pending 상태가 된 경우, `terraform apply`를 다시 실행하거나  
콘솔에서 subscription을 삭제하고 재생성하면 된다.

### 다시 막지 않기 위한 체크 포인트

- SNS → SQS 패턴에서는 queue policy → subscription 순서가 필수
- `depends_on`은 암묵적 의존성으로 해결되지 않는 경우에만 사용하는 것이 원칙이지만,  
  이 경우는 명시적 순서 지정이 필요한 정당한 사용 사례다

---

## 4. terraform_remote_state — output 참조 혼동

### 문제 상황

Mission 4에서 Mission 1의 `private_subnet_ids`를 참조할 때,  
아래 두 가지를 혼동했다.

```hcl
# 잘못된 참조 — local resource처럼 접근
subnet_ids = aws_subnet.private[*].id

# 올바른 참조 — remote state output 경유
subnet_ids = data.terraform_remote_state.mission1.outputs.private_subnet_ids
```

### 원인

Mission 1과 Mission 4는 서로 다른 state 파일을 사용한다.  
한 state에서 다른 state의 리소스를 직접 참조할 수 없고,  
반드시 `outputs.tf`에 노출된 값을 `terraform_remote_state`를 통해 읽어야 한다.

즉, **Mission 1의 `outputs.tf`에 없는 값은 Mission 4에서 참조할 수 없다.**

### 해결 방법

**Mission 1 outputs.tf 확인**  
참조하려는 값이 Mission 1의 `outputs.tf`에 정의되어 있는지 먼저 확인한다.

```hcl
# mission1-foundation/outputs.tf
output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
```

**Mission 4에서 remote_state 선언 후 참조**

```hcl
data "terraform_remote_state" "mission1" {
  backend = "s3"
  config = {
    bucket = "<bucket-name>"
    key    = "deepdive/mission1/terraform.tfstate"
    region = "us-east-2"
  }
}

resource "aws_elasticache_subnet_group" "main" {
  subnet_ids = data.terraform_remote_state.mission1.outputs.private_subnet_ids
}
```

**Mission 5에서는 이 구조가 사라진다**  
Mission 5는 4개 모듈이 하나의 root module 안에 있으므로  
`module.networking.private_subnet_ids`로 직접 참조할 수 있어 `terraform_remote_state`가 불필요하다.

### 다시 막지 않기 위한 체크 포인트

- state 경계를 넘어 값을 전달하려면 반드시 `output` → `remote_state` 경로를 거쳐야 한다
- 참조 대상 state가 먼저 `apply`되어 있어야 remote_state 조회가 성공한다
- Mission 5처럼 단일 root module로 통합하면 이 복잡성 자체가 사라진다

---

## 5. prod 환경 — apply 없이 plan만 확인한 이유

### 문제 상황

prod 환경을 `terraform apply`까지 진행하지 않고 `terraform plan`으로 검증만 했다.

### 원인

prod `terraform.tfvars`의 기본 설정대로 apply하면 아래 리소스가 추가로 생성된다.

| 리소스 | 개수 | 비용 |
|---|---|---|
| NAT Gateway | 2개 (AZ당 1개) | 시간당 과금 |
| ElastiCache `cache.r6g.large` | 3 clusters | dev `cache.t3.micro` 대비 훨씬 높음 |

학습 환경에서는 `terraform plan` 출력으로 dev/prod 구성 차이(NAT 수, node_type, retention 등)를  
코드 수준에서 확인하는 것이 목적이므로, apply 없이 검증을 완료했다.

### prod apply가 꼭 필요한 경우

비용을 최소화하면서 prod apply를 테스트하려면 `terraform.tfvars`에서 아래 값을 임시로 변경한다.

```hcl
# prod/terraform.tfvars — 테스트용 임시 변경
cache_node_type    = "cache.t3.micro"   # r6g.large 대신
cache_num_clusters = 2                  # 3 대신
```

apply 완료 후 즉시 `terraform destroy`로 정리한다.

### 다시 막지 않기 위한 체크 포인트

- prod apply 전에 항상 `terraform plan` 출력에서 리소스 수와 타입을 확인한다
- `cache.r6g.large`와 NAT Gateway 복수 생성은 시간당 비용이 크다
- 학습 환경에서는 plan 검증 → destroy 순서를 원칙으로 삼는다

---

## 6. GitHub 공개 전 — 민감 파일 노출 주의

### 문제 상황

저장소를 GitHub에 공개하기 전에 아래 파일들이 커밋 대상에 포함되어 있는지 점검이 필요하다.

### 원인과 위험성

| 파일 / 디렉토리 | 포함될 수 있는 민감 정보 |
|---|---|
| `*.tfstate`, `*.tfstate.backup` | 리소스 ID, `redis_auth_token` 등 실제 인프라 상태 |
| `.terraform/terraform.tfstate` | provider 초기화 상태 |
| `*.tfvars` | 환경 변수값 (나중에 비밀번호가 추가될 수 있음) |
| `tfplan`, `*.tfplan` | plan 바이너리 — auth_token 등 민감 값 포함 가능 |
| `memory/` 디렉토리 | AWS 계정 정보, MFA 설정, 개인 메모 |

특히 `memory/` 디렉토리는 Claude Code가 학습 진행 중 저장한 컨텍스트 파일이며,  
AWS 계정 ID, MFA 관련 정보, IAM 사용자명이 포함될 수 있다.

### 해결 방법

`.gitignore`에 아래 패턴을 포함한다.

```gitignore
# Terraform generated
.terraform/
*.tfstate
*.tfstate.backup
tfplan
*.tfplan
*.tfvars
*.tfvars.json
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# 개인 / 로컬 환경
memory/           # Claude Code 메모리 — 계정 정보 포함 가능
.codex            # Codex 개인 설정
aws-mfa-main-guide1/  # 강사 제공 MFA 스크립트 (본인 코드 아님)

# OS / 에디터
.DS_Store
.idea/
.vscode/
```

`terraform.tfvars.example` 파일을 대신 커밋해 사용법을 공유한다.

```bash
# gitignore가 제대로 동작하는지 확인
git check-ignore -v memory/ *.tfstate terraform.tfvars
```

**`.terraform.lock.hcl`은 커밋 대상이다.**  
프로바이더 버전을 고정해 `terraform init` 재현성을 보장하므로 gitignore에 포함하지 않는다.

### 다시 막지 않기 위한 체크 포인트

- 첫 커밋 전에 `git status`로 스테이징 대상 파일 목록을 반드시 확인한다
- `git check-ignore -v <파일>` 명령으로 특정 파일이 gitignore에 걸리는지 개별 검증한다
- `memory/` 디렉토리처럼 도구가 자동 생성하는 디렉토리는 공개 전에 내용을 반드시 검토한다
