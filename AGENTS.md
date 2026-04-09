# Terraform Deepdive Working Guide

이 저장소는 Terraform Deepdive 미션을 단계적으로 진행하기 위한 작업 공간이다.

## 문서 우선순위
1. CLAUDE.md — 전역 고정 규칙
2. missions/missionN.md — 현재 미션 상세 요구사항
3. memory/ — 환경, 계정, 진행 기록

## 작업 원칙
- 항상 현재 요청된 미션만 다룬다
- 먼저 plan을 제안하고, 승인 후 코드를 생성한다
- 강사님 미션 내용은 기준으로 따르되, 예시 코드는 그대로 복붙하지 않는다
- 기존 modules는 참고만 가능하며, 현재 미션 시작 구조로 강제 사용하지 않는다
- 현재 미션 범위를 벗어난 리소스는 선구현하지 않는다

## 코드 원칙
- 하드코딩 최소화, 변수화 우선
- 사용자가 따라치기 쉬운 구조 우선
- 불필요한 depends_on 남발 금지
- terraform fmt / validate 기준으로 읽기 쉬운 코드 작성