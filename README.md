# ERP Inbound Validation Pipeline

> n8n + PostgreSQL 기반 ERP 입고 데이터 정합성 검증 및 AI 리포트 자동화

## 1. 프로젝트 한 줄 소개

n8n, PostgreSQL, Docker Compose, Gemini API를 활용하여 **ERP 입고 데이터의 정합성 오류를 자동 검증하고, 상세 CSV 리포트, 요약 CSV 리포트, AI 요약 리포트를 생성하는 업무 자동화 파이프라인**입니다.

ERP 입고 업무에서 자주 발생할 수 있는 수량 오류, 미등록 품목, 미등록 협력사, 발주정보 불일치, 중복 입고 의심 데이터를 SQL로 검증하고, 전산/ERP 운영 담당자가 확인하기 쉬운 형태로 결과를 자동 저장합니다.

---

## 2. 사용 기술

| Category | Stack |
| --- | --- |
| Workflow Automation | n8n |
| Database | PostgreSQL |
| Container | Docker, Docker Compose |
| Query | SQL |
| AI Summary | Gemini API |
| Version Control | Git, GitHub |

---

## 3. 워크플로우 구조

```text
Schedule Trigger
→ Query Validation Result
→ Convert Detail to CSV
→ Write Detail Report
   ├─ Query AI Report Payload
   │  → Generate AI Summary with Gemini
   │  → Extract AI Summary Text
   │  → Convert AI Summary to TXT
   │  → Write AI Summary Report
   │
   └─ Query Validation Summary
      → Convert Summary to CSV
      → Write Summary Report
      → Insert Workflow Run Log
```

워크플로우는 매일 정해진 시간에 실행되며, PostgreSQL에서 ERP 입고 데이터를 검증한 뒤 다음 3가지 결과물을 생성합니다.

1. 상세 오류 CSV 리포트
2. 오류 유형별 요약 CSV 리포트
3. Gemini API 기반 AI 요약 TXT 리포트

상세 리포트는 전체 오류 이벤트를 보존하고, 요약 리포트는 오류 유형별 발생 건수와 영향 입고 건수를 집계합니다.

AI 요약 리포트는 `Query AI Report Payload` 노드에서 조회한 요약용 데이터를 기반으로 생성됩니다.

---

## 4. 핵심 기능

### 4.1 ERP 입고 데이터 검증

입고 데이터, 발주 데이터, 품목 마스터, 협력사 마스터를 기준으로 정합성 오류를 검증합니다.

검증 룰은 다음과 같습니다.

| Error Type | Description |
| --- | --- |
| 수량 음수 | 입고 수량이 0보다 작은 경우 |
| 발주수량 초과 | 입고 수량이 발주 수량보다 많은 경우 |
| 미등록 품목 | 품목 마스터에 존재하지 않는 품목 코드 |
| 미등록 협력사 | 협력사 마스터에 존재하지 않는 협력사 코드 |
| 발주정보 없음 | 발주번호와 품목 조합이 발주 데이터에 없는 경우 |
| 중복 입고 의심 | 동일 입고일, 발주번호, 품목, 협력사, 수량이 모두 같은 데이터가 여러 번 등록된 경우 |

---

### 4.2 상세 리포트와 요약 리포트 분리

리포트는 목적에 따라 상세 리포트와 요약 리포트로 분리했습니다.

| Report | Description |
| --- | --- |
| 상세 리포트 | 모든 오류 이벤트를 보존한 CSV 리포트 |
| 요약 리포트 | 오류 유형별 오류 이벤트 수와 영향 입고 건수를 집계한 CSV 리포트 |
| AI 리포트 | 요약용 검증 데이터를 기반으로 생성한 전산/ERP 운영 담당자용 자연어 리포트 |

하나의 입고 건이 여러 검증 룰에 동시에 걸릴 수 있기 때문에, 상세 리포트에서는 전체 오류 이벤트를 보존합니다.

요약 리포트에서는 오류 유형별로 `오류 이벤트 수`와 `영향 입고 건수`를 함께 제공합니다. 이를 통해 단순 발생 건수뿐 아니라 실제로 영향을 받은 입고 건수도 함께 확인할 수 있습니다.

---

### 4.3 AI 요약 리포트 생성

Gemini API를 활용하여 전산/ERP 운영 담당자용 자연어 리포트를 생성합니다.

AI 리포트는 전체 상세 오류 데이터를 그대로 전달하지 않고, `Query AI Report Payload` 노드에서 조회한 요약용 검증 데이터를 기반으로 생성합니다.

AI 리포트에는 다음 정보가 포함됩니다.

* 금일 검증 결과 요약
* 주요 오류 유형과 발생 건수
* 영향 입고 건수 기준의 우선 확인 대상
* 오류 발생 가능 원인
* 전산/ERP 운영 담당자 관점의 조치 권고
* 재발 방지를 위한 개선 방향

전체 상세 오류 목록은 별도 CSV 파일에서 확인할 수 있도록 분리했습니다.

---

### 4.4 실행 로그 저장

워크플로우 실행 결과는 PostgreSQL의 `workflow_run_log` 테이블에 저장됩니다.

저장 항목은 다음과 같습니다.

| Column | Description |
| --- | --- |
| run_id | 실행 로그 ID |
| workflow_name | 워크플로우 이름 |
| run_at | 실행 시각 |
| detail_report_path | 상세 리포트 저장 경로 |
| summary_report_path | 요약 리포트 저장 경로 |
| total_error_count | 총 오류 이벤트 수 |
| status | 실행 상태 |

---

## 5. 결과 요약

500건의 ERP 입고 샘플 데이터를 기준으로 검증한 결과는 다음과 같습니다.

```text
전체 입고 데이터: 500건
오류 이벤트 수: 191건
영향 입고 건수: 158건
```

`오류 이벤트 수`는 한 입고 건이 여러 검증 룰에 동시에 걸린 경우를 모두 포함한 전체 오류 발생 수입니다.

`영향 입고 건수`는 하나 이상의 오류가 발생한 고유 입고 건수입니다.

생성되는 리포트 파일은 다음과 같습니다.

```text
validation_result_YYYYMMDD.csv
validation_summary_YYYYMMDD.csv
ai_summary_YYYYMMDD.txt
```

실행 결과 예시는 `docs/sample_outputs/` 폴더에서 확인할 수 있습니다.

---

## 6. 실행 방법

### 6.1 프로젝트 실행

프로젝트 루트에서 Docker Compose를 실행합니다.

```bash
docker compose up -d
```

n8n 접속 주소는 다음과 같습니다.

```text
http://localhost:5678
```

---

### 6.2 PostgreSQL 접속 정보

n8n에서 PostgreSQL Credential을 설정할 때 아래 정보를 사용합니다.

```text
Host: erp_postgres
Port: 5432
Database: erp_db
User: erp_user
Password: erp_pass
SSL: Disable
```

---

### 6.3 n8n Workflow 실행

1. n8n에 접속합니다.
2. `n8n_workflows/inbound_validation_pipeline.json` 파일을 import합니다.
3. PostgreSQL Credential을 설정합니다.
4. Gemini API Key를 설정합니다.
5. workflow를 수동 실행하거나 Schedule Trigger를 활성화합니다.
6. `/files/reports/` 경로에 리포트 파일이 생성되는지 확인합니다.

---

## 7. 주요 캡처 이미지

### 7.1 n8n 전체 워크플로우

![n8n Workflow](docs/screenshots/01_n8n_workflow.png)

---

### 7.2 생성된 리포트 파일

![Generated Report Files](docs/screenshots/02_generated_report_files.png)

---

### 7.3 워크플로우 실행 로그

![Workflow Run Log](docs/screenshots/03_workflow_run_log.png)

---

### 7.4 검증 결과 요약

![Validation Summary Result](docs/screenshots/04_validation_summary_result.png)

---

### 7.5 AI 요약 리포트 결과

![AI Summary Report Result](docs/screenshots/05_ai_summary_report_result.png)

---

## 8. 전산팀 직무와의 연결점

이 프로젝트는 전산팀의 ERP 운영 지원 업무를 가정하여 만든 자동화 프로젝트입니다.

실무에서는 입고 데이터, 발주 데이터, 품목 마스터, 협력사 마스터 간의 불일치로 인해 입고 처리 오류, 정산 오류, 재고 데이터 오류가 발생할 수 있습니다. 이 프로젝트는 이러한 오류를 SQL로 사전에 점검하고, n8n을 통해 리포트 생성 과정을 자동화하는 것을 목표로 했습니다.

전산팀 업무와 연결되는 지점은 다음과 같습니다.

* ERP 입고 데이터 정합성 점검
* SQL을 활용한 운영 데이터 검증
* 기준정보 오류 탐지
* 반복 점검 업무 자동화
* 오류 리포트 자동 생성
* 워크플로우 실행 이력 관리
* AI 요약 리포트를 통한 운영 담당자 확인 시간 단축

이를 통해 전산팀에서 자주 수행하는 데이터 점검, 오류 확인, 리포트 작성 업무를 자동화하는 흐름을 구현했습니다.