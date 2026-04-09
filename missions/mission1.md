# Mission 1 — Foundation

## 목표

후속 미션의 기반이 되는 AWS 네트워크/보안/IAM 인프라를 Terraform으로 구축한다.

현재 미션의 핵심은 아래 3가지다.

1. VPC 및 Subnet 기반 네트워크 구성
2. Security Group 기반 접근 제어 구성
3. 이후 미션에서 재사용할 수 있는 Output 확보

---

## 현재 범위

Mission 1에서 구현할 것:

- VPC 1개
- Public Subnet 2개
- Private Subnet 2개
- Internet Gateway 1개
- Elastic IP 1개
- NAT Gateway 1개
- Public Route Table 1개
- Private Route Table 1개
- Route Table Association
- Security Group 3개
  - app
  - redis
  - vpce
- IAM Role 1개
- IAM Role Policy 1개
- IAM Instance Profile 1개
- outputs.tf

---

## 현재 범위에서 제외

Mission 1에서는 아래를 생성하지 않는다.

- EC2
- ALB
- Secrets Manager
- Parameter Store
- SQS / SNS
- ElastiCache Redis
- 모듈화
- dev/prod 멀티 환경 분리
- Terragrunt
- GitHub Actions / CI/CD

즉, Mission 1은 기반 인프라만 만든다.

---

## 실제 실습 환경

- region: us-east-2
- az: us-east-2a, us-east-2c
- environment: dev
- project_name: deepdive
- vpc_cidr: 10.0.0.0/16

추가 환경 규칙:
- Default VPC / Default SG / Default Route Table 수정 금지
- 192.168.x.x CIDR 사용 금지
- 기존 KJW 멀티 VPC 규칙은 현재 미션에 혼용하지 않음

---

## 기본 디렉토리 구조

```text
terraform-deepdive/
└── mission1-foundation/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars