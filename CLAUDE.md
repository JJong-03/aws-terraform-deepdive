# ~/terraform-deepdive/CLAUDE.md
# Terraform Deepdive — Mission 1 (기반 인프라)

---

## 프로젝트 목표

Terraform deepdive Mission 1을 수행한다.

Mission 1의 목표는 후속 미션의 기반이 되는 AWS 네트워크/보안/IAM 인프라를 Terraform으로 구축하는 것이다.

구현 범위:
- VPC
- Public Subnet 2개
- Private Subnet 2개
- Internet Gateway
- Elastic IP
- NAT Gateway
- Route Table / Route Table Association
- Security Group
- IAM Role / Policy / Instance Profile
- Outputs

현재 단계에서는 Mission 1만 수행하고, 이후 Mission 2~5는 output 재사용 구조로 확장한다. :contentReference[oaicite:0]{index=0}

---

## 환경 고정값

- 리전: us-east-2
- 사용 AZ: us-east-2a, us-east-2c만 사용 (2b 금지)
- 환경 기본값: dev
- 프로젝트명 기본값: deepdive
- VPC CIDR 기본값: 10.0.0.0/16
- Terraform 버전: >= 1.5.0
- AWS Provider: ~> 5.0
- AWS 계정 / IAM user / MFA 등 실습 환경 정보는 memory 문서를 따른다

---

## Mission 1 범위 원칙

현재 단계에서는 Mission 1만 수행한다.

지금 생성하지 않을 것:
- EC2
- ALB
- Secrets Manager
- Parameter Store
- SQS / SNS
- ElastiCache Redis
- 모듈화
- dev/prod 멀티 환경 분리

후속 미션은 Mission 1의 output을 재사용하는 구조로 이어진다. 

---

## 구현 기준

- 가용 영역은 하드코딩보다 `data.aws_availability_zones` 사용을 우선하되, 실제 배치는 us-east-2a / us-east-2c 기준으로 맞춘다
- Public Subnet 2개, Private Subnet 2개를 서로 다른 AZ에 배치한다
- NAT Gateway는 첫 번째 Public Subnet에 배치한다
- Public Route Table은 IGW, Private Route Table은 NAT Gateway로 라우팅한다
- Security Group은 app / redis / vpce 3개를 생성한다
- Redis SG는 app SG에서만 6379 허용
- VPCE SG는 app SG에서만 443 허용
- IAM은 EC2 AssumeRole + 실습용 최소 권한 정책 기준으로 작성한다
- output은 다음 미션에서 재사용 가능한 값만 노출한다

구조상 Mission 1은 기반 인프라(VPC, SG, IAM, outputs)를 먼저 만들고, 이후 미션에서 secrets, messaging, cache, 모듈화로 확장하는 흐름을 따른다. 

---

## 코드 규칙

- 하드코딩 최소화, 변수화 우선
- 불필요한 `depends_on` 남발 금지
- Terraform 의존성 기반 설계를 우선
- `terraform fmt` / `terraform validate` 기준으로 읽기 쉬운 코드 작성
- backend bucket 이름은 placeholder로 두고, 사용자가 직접 수정할 값은 주석으로 표시
- 과도한 모듈화는 금지하고, 현재는 따라치기 쉬운 구조를 우선한다
- 이전 실습에서 사용하던 모듈은 참고는 가능하지만, Mission 1 시작 자체는 단순한 flat 구조를 우선한다

---

## 작업 원칙

- 먼저 디렉토리 구조와 파일별 책임을 제안한다
- 그 다음 실제 파일 내용을 생성한다
- 코드 생성 후 반드시 왜 이렇게 구성했는지 설명한다
- 하나의 응답은 하나의 작업 단위로 제한한다
- 다음 단계로 넘어가기 전, 사용자가 직접 실행할 명령어와 검증 포인트를 함께 제시한다
- 현재 미션 범위를 벗어난 리소스는 임의로 추가하지 않는다
- 강사님 미션 내용은 기준으로 따르되, 실습 가이드의 예시 코드는 그대로 복붙하지 않고 검토 후 반영한다

---

## 금지사항

- Default VPC / Default SG / Default Route Table 수정 금지
- 192.168.x.x CIDR 사용 금지
- Mission 1 범위 밖 리소스 선구현 금지
- 콘솔 수동 수정 전제 답변 금지
- 사용자가 바로 따라치기 어려운 과도한 추상화 금지
- 이전 Phase 5 / Phase 6 멀티 VPC, EKS/ECS/Aurora/CloudFront 기준을 현재 미션에 혼용 금지

---

## 기본 디렉토리 구조

```text
terraform-deepdive/
└── mission1-foundation/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars