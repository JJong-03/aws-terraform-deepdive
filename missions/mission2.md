# Mission 2 — Secrets

## 목표

애플리케이션 설정과 민감한 비밀값을 안전하게 관리할 수 있도록
SSM Parameter Store와 Secrets Manager를 Terraform으로 구성한다.

---

## 이 미션에서 다룰 것

- SSM Parameter Store (String 타입)
- Secrets Manager (시크릿 생성 + 버전 관리)
- random_password (DB 비밀번호, Redis auth token 자동 생성)
- sensitive output 처리
- locals를 이용한 경로 prefix / recovery_window 자동 계산

> SecureString은 Secrets Manager와 역할이 겹치므로 Mission 2에서는 제외한다.
> 민감값은 모두 Secrets Manager로 처리한다.

---

## Mission 1에서 필요한 값

Mission 2는 Mission 1 완료를 전제로 하지만,
네트워크/SG 정보를 직접 참조하지 않으므로 **독립 구성**이다.

Mission 1 output은 Mission 4(ElastiCache)에서 직접 참조한다.

---

## 현재 범위

### SSM Parameter Store

경로 형식: `/${project_name}/${environment}/<category>/<key>`

| 경로 | 타입 | 값 |
|---|---|---|
| `/deepdive/dev/app/port` | String | "8080" |
| `/deepdive/dev/app/log_level` | String | "info" |
| `/deepdive/dev/db/port` | String | "5432" |
| `/deepdive/dev/db/name` | String | "deepdive" |
| `/deepdive/dev/redis/port` | String | "6379" |

### Secrets Manager

시크릿 이름 형식: `${project_name}/${environment}/<type>`

| 시크릿 이름 | 값 구조 |
|---|---|
| `deepdive/dev/db-credentials` | JSON: `{"username": "deepdive_admin", "password": "<random>", "dbname": "deepdive"}` |
| `deepdive/dev/redis-auth` | 문자열: `<random token>` |

> DB credentials JSON에 `dbname`을 포함한다.
> username + password만으로는 애플리케이션이 연결 대상 DB를 특정할 수 없으며,
> 이후 DB 연동 확장 시 시크릿 하나로 접속 정보를 완결 있게 제공하기 위한 구조다.

### random_password 정책

| 대상 | 길이 | 특수문자 |
|---|---|---|
| DB password | 20 | true (`!#$%&*()-_=+[]<>:?`만 허용, `@`, `/`, `"` 제외) |
| Redis auth token | 32 | false (ElastiCache AUTH token 공백/따옴표 미지원) |

### recovery_window_in_days

| 환경 | 값 |
|---|---|
| dev | 7일 |
| prod | 30일 |

`locals`에서 `var.environment == "prod" ? 30 : 7`로 자동 계산.
tfvars에 별도 값 입력 불필요.

---

## 현재 범위에서 제외

- SecureString (Secrets Manager로 역할 통합)
- terraform_remote_state (Mission 2는 독립 구성)
- Secrets Manager 리소스 정책 (실습 범위 외)
- EC2, ALB, ElastiCache 등 상위 리소스

---

## 기본 디렉토리 구조

```text
terraform-deepdive/
└── mission2-secrets/
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
- `ssm_prefix = "/${var.project_name}/${var.environment}"`
- `recovery_window = var.environment == "prod" ? 30 : 7`

---

## 네이밍 / 태그 규칙

| 구분 | 형식 | 예시 |
|---|---|---|
| Secrets Manager 시크릿 이름 | `project/environment/type` | `deepdive/dev/db-credentials` |
| SSM Parameter 경로 | `/project/environment/category/key` | `/deepdive/dev/app/port` |
| Name 태그 / name_prefix | `KJW-project-environment` | `KJW-deepdive-dev` |
| provider default_tags | Owner, Environment, Project | Mission 1과 동일 |

---

## backend 설정

Mission 1과 동일한 S3 bucket, key만 분리:

```hcl
backend "s3" {
  bucket = "REPLACE_ME_SAME_AS_MISSION1"  # Mission 1 backend에 입력한 bucket 이름 동일 입력
  key    = "deepdive/mission2/terraform.tfstate"
  region = "us-east-2"
}
```

---

## sensitive output 처리

`redis_auth_token`은 `sensitive = true`로 설정한다.
단, `terraform.tfstate`에는 평문으로 저장되므로 S3 bucket의 암호화 및 접근 제어 설정이 필요하다.

---

## 예상 산출물 (outputs)

| output 이름 | sensitive | 설명 |
|---|---|---|
| `ssm_parameter_prefix` | false | "/deepdive/dev" |
| `db_credentials_secret_arn` | false | DB credentials secret ARN |
| `db_credentials_secret_name` | false | 콘솔 확인 / 참조용 시크릿 이름 |
| `redis_auth_secret_arn` | false | Redis auth secret ARN |
| `redis_auth_token` | **true** | Mission 4 auth_token 파라미터로 직접 사용 |

---

## 예상 resource 수

```
random_password × 2                        2
aws_ssm_parameter × 5                      5
aws_secretsmanager_secret × 2              2
aws_secretsmanager_secret_version × 2      2
────────────────────────────────────────────
합계                                       11 resources
```

---

## Mission 4 연동 방식

Mission 4(ElastiCache Redis)에서 Mission 2 output을 아래와 같이 참조한다:

```hcl
data "terraform_remote_state" "mission2" {
  backend = "s3"
  config = {
    bucket = "<동일 bucket>"
    key    = "deepdive/mission2/terraform.tfstate"
    region = "us-east-2"
  }
}
```

| Mission 4 파라미터 | 참조값 |
|---|---|
| `auth_token` | `data.terraform_remote_state.mission2.outputs.redis_auth_token` |

Mission 4에서는 Mission 1 state도 별도로 참조한다 (subnets, sg_redis_id).

---

## 검증 포인트

| 단계 | 확인 사항 |
|---|---|
| `terraform validate` | "Success! The configuration is valid." |
| `terraform plan` | "Plan: 11 to add, 0 to change, 0 to destroy" |
| `terraform output` | 4개 비민감 output 확인 |
| `terraform output -raw redis_auth_token` | sensitive 값 직접 조회 |
| SSM 콘솔 | Parameter Store `/deepdive/dev/` 하위 5개 파라미터 |
| Secrets Manager 콘솔 | `deepdive/dev/db-credentials`, `deepdive/dev/redis-auth` 확인 |
| DB 시크릿 구조 확인 | `aws secretsmanager get-secret-value --secret-id deepdive/dev/db-credentials` |
