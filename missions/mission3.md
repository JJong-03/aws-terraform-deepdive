# Mission 3 — Messaging

## 목표

비동기 메시징 구조를 위해 SNS + SQS + DLQ 기반 파이프라인을 Terraform으로 구성한다.

---

## 이 미션에서 다룰 것

- SNS Topic (Standard)
- SQS Queue + Dead Letter Queue
- `aws_sqs_queue_redrive_allow_policy` (DLQ별 redrive 소스 제한)
- `data "aws_iam_policy_document"` + Queue Policy
- SNS → SQS subscription (fan-out)
- `for_each`를 이용한 다중 큐 구성

---

## 이전 미션 의존성

Mission 3는 아래를 전제로 한다:
- Mission 1 완료
- Mission 2 완료

SNS/SQS는 VPC 외부 서비스이므로 Mission 3는 **독립 구성**이다.
Mission 1 / Mission 2 remote_state 참조 없음.

---

## 전체 아키텍처

```
SNS Topic (events)
  ├── SQS: order        ←→ DLQ: order-dlq
  └── SQS: notification ←→ DLQ: notification-dlq
```

---

## 현재 범위

### SNS Topic

| 항목 | 값 |
|---|---|
| 이름 | `KJW-deepdive-dev-sns-events` |
| 타입 | Standard |

### SQS 큐 맵 (`for_each` 기준)

| 큐 키 | visibility_timeout | max_receive_count | message_retention |
|---|---|---|---|
| `order` | 30초 | 3 | 345600초 (4일) |
| `notification` | 60초 | 5 | 345600초 (4일) |

> `message_retention_seconds`는 큐마다 명시적으로 관리하기 위해 map에 포함.
> 향후 큐별 차등 적용이 필요할 때 map 값만 수정하면 된다.

### DLQ 설정

| 항목 | 값 |
|---|---|
| `message_retention_seconds` | 1209600초 (14일, 공통) |
| redrive 허용 | `byQueue` — 자신의 메인 큐 ARN만 허용 |

`aws_sqs_queue_redrive_allow_policy`로 각 DLQ가 수신할 수 있는 source queue를 제한한다.
`order-dlq`는 `order` 큐만, `notification-dlq`는 `notification` 큐만 허용.

### Queue Policy

`data "aws_iam_policy_document"` + `aws_sqs_queue_policy` 조합 사용.

- **Principal**: `sns.amazonaws.com`
- **Action**: `sqs:SendMessage`
- **Condition**: `aws:SourceArn == SNS topic ARN` (다른 SNS topic 전송 차단)

### SNS Subscription

| 항목 | 값 |
|---|---|
| Protocol | "sqs" |
| `raw_message_delivery` | false |
| `depends_on` | `[aws_sqs_queue_policy.main]` |

> `raw_message_delivery = false` 이유:
> SQS에 SNS envelope JSON 형태로 메시지가 전달된다.
> MessageId, TopicArn, Timestamp 등의 메타데이터가 포함되어 실습 중 메시지 구조 확인에 유리하다.
> 프로덕션에서 raw body만 처리하는 컨슈머는 true로 전환한다.
>
> `depends_on` 이유:
> queue policy 생성 전에 subscription이 먼저 만들어지면 SNS 확인 메시지가 거부되어
> subscription이 Pending 상태로 남을 수 있다. 명시적 순서 보장이 필요하다.

---

## 현재 범위에서 제외

- FIFO Queue / FIFO SNS Topic
- 구독 필터 정책 (Filter Policy)
- SNS → Lambda, HTTP/S 구독
- SQS long polling 설정
- 모듈화

---

## 기본 디렉토리 구조

```text
terraform-deepdive/
└── mission3-messaging/
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

---

## 네이밍 / 태그 규칙 (Mission 1/2와 동일)

| 구분 | 형식 | 예시 |
|---|---|---|
| SNS topic 이름 | `KJW-project-environment-sns-<role>` | `KJW-deepdive-dev-sns-events` |
| SQS 큐 이름 | `KJW-project-environment-sqs-<key>` | `KJW-deepdive-dev-sqs-order` |
| DLQ 이름 | `KJW-project-environment-sqs-<key>-dlq` | `KJW-deepdive-dev-sqs-order-dlq` |
| Name 태그 | `local.name_prefix` 기준 | `KJW-deepdive-dev-...` |
| provider default_tags | Owner, Environment, Project | Mission 1/2와 동일 |

---

## backend 설정

Mission 1/2와 동일한 S3 bucket, key만 분리:

```hcl
backend "s3" {
  bucket = "REPLACE_ME_SAME_AS_MISSION1"
  key    = "deepdive/mission3/terraform.tfstate"
  region = "us-east-2"
}
```

---

## 예상 resource 수

```
aws_sns_topic.main                              1
aws_sqs_queue.dlq × 2 (for_each)               2
aws_sqs_queue.main × 2 (for_each)              2
aws_sqs_queue_redrive_allow_policy × 2          2
aws_sqs_queue_policy.main × 2 (for_each)       2
aws_sns_topic_subscription.main × 2 (for_each) 2
──────────────────────────────────────────────────
합계                                           11 resources
data source (aws_iam_policy_document × 2)
```

---

## 예상 산출물 (outputs)

| output 이름 | 타입 | 설명 |
|---|---|---|
| `sns_topic_arn` | string | SNS topic ARN |
| `sqs_queue_urls` | map(string) | `{ order = "...", notification = "..." }` |
| `sqs_queue_arns` | map(string) | `{ order = "...", notification = "..." }` |
| `dlq_queue_arns` | map(string) | `{ order = "...", notification = "..." }` |

---

## 검증 포인트

| 단계 | 확인 사항 |
|---|---|
| `terraform validate` | "Success! The configuration is valid." |
| `terraform plan` | "Plan: 11 to add, 0 to change, 0 to destroy" |
| `terraform output` | 4개 output 출력 확인 |
| SNS 콘솔 | KJW-deepdive-dev-sns-events 토픽 생성 확인 |
| SQS 콘솔 | order, notification, order-dlq, notification-dlq 총 4개 큐 확인 |
| 구독 확인 | SNS topic > Subscriptions → 2개 SQS 구독 Confirmed 상태 |
| redrive 제한 확인 | SQS > order-dlq > Redrive allow policy → order queue만 허용 확인 |
| DLQ 연결 확인 | SQS > order 큐 > Dead-letter queue → order-dlq 연결 확인 |
| 메시지 전송 테스트 | SNS 콘솔 > Publish message → 각 SQS에서 수신 확인 |
| SNS envelope 확인 | SQS > Poll messages → MessageId, TopicArn 포함된 JSON 봉투 확인 |
