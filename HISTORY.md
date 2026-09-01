# HISTORY

`query` 변경 이력. 새 항목은 **맨 위에** 추가.

형식:

```
## YYYY-MM-DD — 한 줄 요약

무엇이 왜 바뀌었는지. 영향받는 하위 산출물/대시보드가 있으면 명시.
```

---

## 2026-09-01 — 예약쿼리에 실패 로깅 추가 (run_log 정상화)

`query_run_log`는 만들어진 이래 `status`가 항상 `SUCCESS`였다. MERGE가 실패하면
스크립트가 중단돼 로그 INSERT 자체가 실행되지 않기 때문이다. `error_message`와
`updated_rows`도 한 번도 채워진 적이 없다.

`03_merge_daily.sql` 전체를 `BEGIN ... EXCEPTION WHEN ERROR THEN ... END` 로 감쌌다.

- **실패해도 `FAIL` 행이 남는다.** BigQuery 스크립트는 문장 단위로 커밋되므로
  `RAISE` 이전에 넣은 INSERT는 살아남는다. `RAISE`로 오류를 재발생시키지 않으면
  예약쿼리가 "성공"으로 끝나 실패 메일이 오지 않으므로 반드시 재발생시킨다.
- **`updated_rows`가 채워진다.** MERGE 직후 `@@row_count`(INSERT + UPDATE 총합)에서
  순증분을 빼면 갱신 행수가 나온다.
- **적재 0행은 `EMPTY`로 구분한다.** 0행일 때 실패처리(RAISE)는 하지 않기로 했다.
  DTS 재시도로 로그가 중복되고, 원본이 늦게 올라오는 날에도 실패로 찍히기 때문이다.
  0행 알림은 `monitoring/`의 아침 Slack 요약이 담당한다.

`50_run_log.sql`의 `status` 주석에 `EMPTY`를 추가했다. 다만 이 파일은
`CREATE TABLE IF NOT EXISTS`이고 테이블이 이미 있으므로 주석 변경은 배포되지 않는다.

`monitoring/signup_90days_digest`가 `error_message`를 읽어 `FAIL` 시 원인 문구를
Slack에 그대로 띄운다. 이 변경과 짝이다.

**2026-09-01 23:09 배포 완료.**

검증 순서:
1. 예약쿼리가 23:00에 옛 버전으로 정상 실행돼 오늘치 614행이 이미 들어와 있었다.
2. 새 버전을 수동 1회 실행했다. 전량 키 일치라 UPDATE 경로만 탔고
   `inserted_rows = 0`, **`updated_rows = 614`** 가 기록됐다. 지금까지 항상 `NULL`이던
   컬럼이 처음으로 채워졌다. 두 번 실행해 결과가 같은 것으로 멱등성도 확인했다.
3. `bq update --transfer_config` 로 예약쿼리 본문을 파일 그대로 밀어넣었다.
   콘솔 복붙 대신 이 방식을 쓰면 바이트 단위로 일치한다. `bq show` 대조로 확인했다.
   스케줄(`every day 14:00`)·실패메일 설정·다음 실행 시각은 그대로다.

반영 방법을 README의 주의 항목에 적어뒀다. SQL 안에 백틱이 있어 셸을 거치면
명령치환으로 해석될 수 있으므로 `subprocess`로 인자를 직접 넘긴다.

## 2026-09-01 — signup_2025 콘솔 저장쿼리 삭제

`80_year_merge`, `81_year_detail_merge` 저장쿼리를 콘솔에서 삭제했다.
두 쿼리 모두 선두가 `DROP TABLE`이라 목록에서 무심코 열어 실행하면 테이블이 날아간다.
SSOT를 로컬로 정한 이상 콘솔에 죽은 사본을 남겨둘 이유가 없다고 판단했다.

내용은 `signup_2025/` 아래 파일에 그대로 있다. 다시 쓸 일이 생기면 복붙하면 된다.
BigQuery의 테이블·뷰는 건드리지 않았다. 저장쿼리(콘솔 북마크)만 지웠다.

## 2026-09-01 — 콘솔 저장쿼리 6개 반입 완료, search_console 폴더 신설

콘솔에만 있던 6개를 반입해 로컬이 콘솔 저장쿼리 17개를 전부 담게 됐다.

| 반입 | 경로 |
|---|---|
| `01_ext_table_조회` | `signup_90days/90_ext_table_check.sql` |
| `10_ext_파일별컬럼확인` | `signup_90days/91_ext_column_check.sql` |
| `10_view_테이블조회` | `signup_90days/92_view_table_check.sql` |
| `12_테이블리스트` | `signup_90days/93_table_list.sql` |
| `SearchConsole_02_create_view` | `search_console/02_create_view.sql` |
| `SearchConsole_03_dashboard_join_view` | `search_console/03_dashboard_join_view.sql` |

읽어보고 정정한 것:

- **`_tmp_onefile_schema`는 정리 대상이 아니었다.** `91_ext_column_check.sql`이 매 실행마다
  `CREATE OR REPLACE`로 다시 만드는 일회용 외부 테이블이다. 앞서 "방치된 잔여물"로
  적었던 것을 바로잡는다. 6개를 읽기 전에 지웠다면 그 유틸이 깨졌을 것이다.
- **SearchConsole 2개는 미배포 초안이다.** 전체가 `/* */`로 감싸여 있어 실행해도 아무 일도
  일어나지 않는다. `carbiz-6f7fc.searchconsole` 데이터셋에는 원본 export 테이블만 있고
  `v_page_daily` / `v_monthly_summary` / `v_yoy_monthly` / `v_dashboard_main` 중
  실제로 존재하는 것은 하나도 없다. 파일 선두에 그 사실을 적어뒀다.
- `92_view_table_check.sql`은 `SELECT *`에 `LIMIT`이 없어 그대로 돌리면 약 48MB를 스캔한다.
  주석 처리된 `WHERE`/`LIMIT` 중 하나를 푸는 것을 전제로 만든 쿼리다. README에 적었다.

부수: 프로젝트에 `analytics_429050434`, `analytics_528628070`, `analytics_528629362`,
`ga4_mkt_analytics` 데이터셋이 더 있다. 현재 이 작업장의 범위 밖이며 README에 명시만 해뒀다.

SearchConsole 파일에 남아 있던 도메인 지식은 보존한다: `query` dimension을 넣으면
클릭/노출이 과소집계되므로 정확한 수치는 `query`를 빼고 집계해야 하고,
`avg_position`은 `SAFE_DIVIDE(sum_position, impressions)`로 계산한다.

## 2026-09-01 — signup_2025 미사용 확정, 80/81에 표시

`signup_2025` 데이터셋이 2026-02 이후 갱신이 멈춘 것을 확인했다. 현재 쓰지 않는다.

| 테이블 | 행 | 최종수정 |
|---|---|---|
| `signup_2025.signup_2025` | 3,455 | 2026-02-05 |
| `raw_signup_2025` | 3,455 | 2026-02-12 |
| `raw_signup_detail_2025_v1` | 3,824 | 2026-02-26 |

출처가 불명이던 `signup_2025.signup_2025`는 2026-02-05에 한 번 적재된 일회성 수동
적재본이었다. 이 저장소의 어떤 SQL도 그것을 만들지 않는다.

`80`/`81` 선두에 미사용 표시를 넣고 README에도 명시했다. `04`와의 파생 드리프트
(세그먼트 4종이 `80`에만 있고, 테스트계정 정규식이 다르며, `plan_status`/`is_paid_flag`가
없음)는 미사용이므로 맞추지 않는다. 다시 쓰게 되면 그때 `04` 기준으로 재작성한다.

부수 발견: `signup_90days._tmp_onefile_schema`는 스키마 확인용 임시 외부 테이블로
2026-02-11 생성 후 방치돼 있다. `dt=2026-01-29` 하루치만 가리키며 어느 SQL도
참조하지 않는다. README의 정리 대상에 올렸다. 외부 테이블이라 삭제해도 GCS 원본은 남는다.

## 2026-09-01 — 05/07 공통 파생을 04로 통합

`05`와 `07`이 파생컬럼 계산을 통째로 복붙해 갖고 있었다. 한쪽만 고치면 즉시 어긋나는
구조라 공통분을 `04`로 올렸다.

`04`로 이동한 것 (10개 컬럼):
`is_churned_date`, `days_to_churn`, `signup_year`, `signup_month`, `signup_year_month`,
`churn_before_activation`, `churn_before_activation_flag`, `is_pre_paid_flag`,
`is_withdrawn_company`, `rn`

`is_churned_date`는 `05`/`07`이 각자 `churn_by_company` CTE + `LEFT JOIN`으로 만들던
값인데, `04`에서 윈도우 함수로 계산하니 JOIN 자체가 사라졌다.

`05`/`07`에 남은 것은 중복기업 판정뿐이며, 둘의 차이는 두 곳으로 좁혀졌다.
1) 행 범위: `05`는 `rn = 1`, `07`은 필터 없음
2) dedup `PARTITION`: `05`는 `company_name_norm`, `07`은 `snapshot_date` + `company_name_norm`
이 두 줄이 다른 이유를 두 파일 상단 주석에 적어뒀다. `PARTITION BY`가 다르고
BigQuery 테이블 함수로는 파티션 키를 인자로 받을 수 없어 표준 SQL로는 더 못 줄인다.

분량: `05` 197 -> 81줄, `07` 139 -> 85줄, `04` 202 -> 248줄. 순 -52줄.

`07`은 삭제 후보가 아님을 확인했다. `04`에는 중복기업 판정이 없어 특정 시점 현황을
셀 수 없고, `05`를 `rn = 1`로 필터해도 `07`이 나오지 않는다. `05`는 회사마다 최신 날짜가
달라도 서로 비교하지만 `07`은 같은 `snapshot_date` 안에서만 비교하기 때문이다.

검증:
- 출력 컬럼 집합 동일. `05` 82/82, `07` 82/82, `06` 13/13, 유실 0. `04`만 10개 추가.
- `monthly_summary` 수치가 현재 배포본과 11개월 전부 일치.

미배포. 배포 순서는 `04` -> `05` -> `07`이며 `04`를 먼저 올리지 않으면 하위 뷰가
`rn` 컬럼을 못 찾아 실패한다. `06`은 파일이 안 바뀌었으므로 배포 불필요다.

## 2026-09-01 — 중복기업 판정의 비결정성 제거 (tiebreak 추가)

`05`/`07`의 `duplicate_keep_rank`가 정렬키 4개(차량수·운행수·누적거리·사용자수)만
쓰고 있어서, 활동량이 전부 0인 빈 계정끼리 같은 회사명으로 묶이면 `ROW_NUMBER`의
순위가 실행마다 달라졌다. 같은 뷰를 조회할 때마다 다른 계정이 살아남는다.

실측으로 확인한 것:
- 같은 그룹(`낙현회사`, 7개 계정)에서 세 번 실행에 세 번 다른 계정이 남았다
  (`J1247` -> `Q229` -> `A1007`).
- 해당 그룹들은 정렬키 4개가 전부 동점이었다 (차량 1 / 운행 0 / 거리 NULL / 사용자 1).
- 총계는 흔들리지 않는다. 그룹당 정확히 1개만 남으므로 `company_count`와
  `paid_conversion_rate`는 그대로다. 흔들리는 것은 개별 기업 목록·드릴다운이다.

`ORDER BY` 끝에 `company_code`를 붙여 결정적으로 만들었다. 어느 계정이 남느냐는
임의지만 항상 같은 계정이 남는다. 알려진 7개 동점 그룹 전부에서 최소 `company_code`가
유지되는 것을 확인했다.

판정 기준 자체는 바꾸지 않았다. "먼저 가입한 계정을 유지" 같은 의미 부여는 별도 결정이다.

## 2026-09-01 — 파일명 ASCII 통일, 데이터셋 단위 폴더 분리, README 작성

BigQuery 콘솔의 저장된 쿼리 17개와 로컬 12개를 대조해보니 로컬이 부분집합이었고
이름 체계도 어긋나 있었다. 대응 관계를 고정하고 SSOT를 로컬로 못박았다.

- 파일명을 ASCII로 통일. 한글·공백 파일명은 셸과 도구에서 계속 깨졌다.
- `03`을 용도별로 분리: `03_merge_daily.sql`(예약쿼리 `update_daily` 실물 사본,
  바이트 단위 동일함을 확인) / `03b_merge_backfill.sql`(수동 소급용).
  드리프트가 아니라 용도가 둘이었다.
- `80`/`81`을 `signup_2025/`로 이동. 데이터셋 단위 폴더 규칙에 맞춘다.
- 번호 대역 확정: `0x` 파이프라인 / `5x` 운영 / `8x` 연간 / `9x` 조회·점검 유틸.
  콘솔의 `10_` 중복을 `9x`로 해소한다.
- `README.md`를 실제 내용으로 작성. 데이터 흐름, 파일별 역할, 콘솔 저장쿼리 대응표,
  배포 순서, 예약쿼리 어긋남 확인 방법을 담았다.
- `CLAUDE.md`에 "SSOT는 로컬" 규칙 추가.

예약 쿼리는 `update_daily` 하나뿐이며 매일 23:00 KST(14:00 UTC), `asia-northeast3`에서
실행된다. 실패 시 메일 발송이 켜져 있다.

콘솔에만 있어 아직 반입하지 못한 6개는 `README.md`의 미반입 표에 경로까지 적어뒀다.
저장된 쿼리는 `bq` CLI로 읽을 수 없어 콘솔에서 직접 복사해야 한다.

부수: `001_ext_table.sql` -> `01_ext_table.sql` 리네임이 직전 커밋(유료 판정 단일화)에
섞여 들어갔다. 무관한 변경이지만 되돌리지 않고 여기 기록만 남긴다.

## 2026-09-01 — 유료 판정 단일화: plan_status 신설, is_paid_cond 제거

유료 판정이 `04`의 `is_paid_cond`와 `05`/`07`의 `is_paid_flag` 두 벌로 나뉘어 서로 다른
조건을 쓰고 있었다. 요금제 기준 단일 판정 `plan_status`(free/trial/paid)를 `04`에 신설하고
`is_paid_flag`를 여기서만 정의해 하위 뷰가 상속하도록 바꿨다.

판정 규칙 (BigQuery 실측으로 6개 조합 전수 확인):
- `pricing_plan = 'FREE'` -> free. 체험 플래그 무시.
  FREE + 체험중 108개사는 전부 `user_count = 0`인 탈퇴/미개통 계정이며 실제 체험이 아니다.
- 그 외 요금제(PLUS/PREMIUM)는 `is_trial_active` 참이면 trial, 아니면 paid.
  PLUS + 체험중 2개사(`contract_period = '무료체험'`)가 실재하므로 premium 한정은 쓸 수 없다.
- `contract_period` / `contract_type` 파싱은 유료 판정에서 완전히 제외.

발견한 것:
- `pricing_plan` 실제 값은 대문자 `FREE`/`PLUS`/`PREMIUM`이다. 기존 `04`의
  `pricing_plan = 'premium'` 비교문은 한 번도 참이 된 적 없는 죽은 코드였고,
  `is_paid_cond`의 `COALESCE(pricing_plan,'free') != 'free'` 조건은 FREE 요금제를
  전부 유료로 판정하고 있었다. 이 값을 먹는 `days_since_paid`가 오염돼 있었다.
- 대시보드 KPI(`06`)는 `05`의 `is_paid_flag`를 쓰므로 전환율 자체는 오염되지 않았다.
  다만 `06` 안에서 `paid_count`(=494)와 `paid_conversion_rate`의 분자(=496)가
  서로 다른 기준이었다. 이제 둘 다 496으로 일치한다.

영향:
- `paid_conversion_rate` 불변 (496/2399). 구/신 유료 판정은 기업 단위로 100% 일치함을 대조 확인.
- `paid_count`/`paid_ratio` 494 -> 496.
- `days_since_paid` 값이 크게 바뀐다. 유료 도달 기업만 값이 생긴다.
- `is_paid_cond` 컬럼 소멸. Looker에서 이 필드를 참조 중이면 깨진다. 배포 전 확인 필요.

**2026-09-01 배포 완료.** 콘솔에서 04 -> 05 -> 07 -> 06 순으로 본문을 교체해 실행했다.
배포본과 로컬 파일이 일치함을 확인했고(`bq show`의 `view.query` 대조),
`view_signup_90days_monthly_summary`에서 `trial + free + paid = company_count`가
전월 정확히 일치하는 것으로 검증했다. 배포 전에는 이 합이 맞지 않았다.

참고: BigQuery는 뷰를 저장할 때 `AS` 직후의 선두 주석 블록을 떼어낸다.
배포본과 로컬을 diff하면 그 주석만 차이로 잡히므로 드리프트로 오해하지 않는다.

## 2026-09-01 — BigQuery 실행 원칙을 작업장 규칙으로 명문화

`gcloud`/`bq` CLI를 붙이면서 에이전트가 BigQuery를 직접 실행할 수 있게 됐다.
기본은 실행하지 않고 SQL 파일만 산출하며, dry-run과 스키마 조회는 무승인,
데이터를 읽는 쿼리와 되돌릴 수 없는 실행은 매번 사전 승인하도록 `CLAUDE.md`에 규칙을 넣었다.
`02`/`80`은 선두 `DROP TABLE` 때문에 통째 실행 금지로 명시.
dry-run은 컴파일 체크지 런타임 검증이 아니라는 한계도 함께 적었다.

## 2026-09-01 — signup_90days 운영 쿼리 12개 as-is 반입

현재 BigQuery에서 돌고 있는 쿼리를 수정 없이 그대로 커밋. 이후 개선 diff의 기준점으로 삼기 위함.
`signup_90days`(일별 스냅샷 파이프라인) 10개 + `signup_2025`(연간 분석) 2개.
1차 파악에서 확인된 미해결 사항은 아직 손대지 않음:
- `is_paid` 정의 2종 불일치 (04 `is_paid_cond` vs 05/07 `is_paid_flag`) — 06 KPI 전환율에 영향
- `02`/`80` 선두 `DROP TABLE`이 raw 누적분 전량 삭제
- `03` 로컬본/예약쿼리본 2개 드리프트, `05`/`07` 로직 복붙
- `80`/`81`은 `signup_2025` 데이터셋인데 `signup_90days/` 폴더에 위치

## 2026-08-31 — 기존 산출물 아카이브, 구조만 남기고 재시작

이전 산출물(`signup_90days/` SQL 10개 + 문서, 커밋 17개)은 `../_archive/20260831/query/`로 이동.
작성 맥락이 남지 않아 이어받지 않고 다시 만들기로 함. 파이프라인 구조 설명과
중복/테스트/탈퇴 판정 로직 문서는 참고 가치가 있어 아카이브에서 조회 가능.

관련: ../decisions/ADR-0002-archive-and-restart.md

## 2026-08-31 — 작업장 생성

로컬 깃 초기화, 템플릿 문서 추가.
