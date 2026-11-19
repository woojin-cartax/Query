# weekly — CX 주간보고 가입·결제 집계

CX 주간보고(목~수)에 넘기는 CSV 를 만드는 스크립트. 2026-10-29 부터 scratchpad 에서 돌리다가
두 번 지워져 2026-11-19 에 여기로 옮겼다. 같은 회사 판정은 `../company_match_decisions.csv`,
공통 로직(그룹핑·BigQuery 호출)은 `../92_weekly_signup.py` 를 쓴다.

모든 스크립트는 BigQuery 를 **읽는다** — 실행마다 사전 승인 (`../../CLAUDE.md`).

| 파일 | 만드는 것 |
|---|---|
| `cx_list.py <export.xlsx> <snapshot> <week_start> <out.csv>` | 주간 가입 목록 v4 (신규/재가입/중복/테스트) + 판정 요청 목록 |
| `ytd.py <export.xlsx> <out.csv>` | `weekly_ytd_2026.csv` (연초부터 주별) |
| `funnel.py <export.xlsx> <out_dir>` | `weekly_funnel_12w.csv`, `signup_cohort_12w.csv` |
| `detail.py <list.csv> <snapshot>` | 재가입·중복 상세(이전 계정 · 누적 운행 · 경과일), 노션 표용 |
| `new_payments.sql` | 주간 신규 결제(무료→유료 전환) 목록. 금액은 없음 |
| `combo.py <out.png>` | 노션용 8주 유입·가입 차트 (값은 파일 안 상수) |

## 매주 바꾸는 상수

- `ytd.py` · `funnel.py`: `SNAP`(최신 스냅샷 = 주 마지막 수요일), `END`(같은 날).
  `funnel.py` 의 `W0` 는 12주 창 시작 — 한 주씩 민다.
- `new_payments.sql`: 날짜 3곳 (전주 수요일, 이번 주 목·수).
- `combo.py`: `W`·`T`(유입, 주간보고 기록)·`S`(가입 = ytd 신규가입_기업수)·`NOTE`, 오른쪽 축 상한.

## 검증

새로 바꾸기 전에 지난주 상수로 한 번 돌려 docs/data 의 기존 CSV 와 `diff` 가 없는지 본다.
퍼널·코호트 헤더의 "(10/28까지)" 는 옛 문구 그대로다(컬럼명 호환 때문에 유지).
