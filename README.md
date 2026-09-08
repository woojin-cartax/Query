# query

BigQuery 쿼리 관리. 데이터셋 단위 SQL 폴더.

## 목적

BigQuery에 배포되는 SQL의 **단일 진실 공급원(SSOT)**이다.
콘솔에서 직접 고치지 않는다. 여기서 고치고 배포한다.

### 콘솔 저장쿼리를 두지 않는 이유

파이프라인 쿼리(`01`~`07`)는 콘솔 저장쿼리를 **두지 않는다.** 2026-09-01에 전부 삭제했다.

저장쿼리는 파일과 분리된 사본이라 자동으로 동기화되지 않는다. 배포할 때마다 콘솔에서도
갈아끼워야 하고, 한 번만 빼먹으면 어긋난다. 어긋난 저장쿼리를 누군가 실행하면
뷰가 과거 정의로 되돌아간다. 얻는 것은 "목록에서 클릭 한 번"이고 치르는 것은
매번 이중 작업이라 남는 장사가 아니다.

조회·점검용(`50`, `51`, `90`~`93`)은 남겨둔다. 뷰나 테이블을 바꾸지 않으므로
본문이 낡아도 사고가 나지 않고, 콘솔에서 바로 실행하는 편이 편하다.

필요하면 언제든 파일 내용을 붙여넣어 다시 저장할 수 있다. 원본은 여기에 있다.

## 데이터 흐름 — signup_90days

```
GCS  gs://cartax-biz_signup_90days/dt=*            일별 parquet 스냅샷
  → ext_signup_90days       외부 테이블 (hive 파티션, 파티션 필터 강제)
  → raw_signup_90days       네이티브 (PARTITION snapshot_date / CLUSTER company_code)
        ↑ 예약쿼리 update_daily 가 매일 23:00 KST 에 MERGE
  → view_signup_90days                        전체 히스토리 + 파생컬럼
       ├→ view_signup_90days_latest           회사별 최신 1행 + 중복/이탈 판정
       │      └→ view_signup_90days_monthly_summary   가입월별 KPI
       ├→ view_signup_90days_by_snapshot      스냅샷 날짜별 전체 (latest의 rn=1 미적용판)
       └→ view_signup_90days_monthly_base     월말 기준일 x 회사. 월별 리포트 토대
              ├→ view_signup_90days_monthly_summary   월별 요약 (표1)
              └→ view_signup_90days_monthly_by_plan   월별 요금제 분포 (표2)
```

`signup_2025`는 연간 분석용 별개 데이터셋이며 위 흐름과 독립이다.

## 파일 구조

`콘솔 저장쿼리` 열은 BigQuery 콘솔의 저장된 쿼리 이름이다. 파일명과 다르므로 이 표로 대응한다.

### signup_90days/

| 파일 | 콘솔 저장쿼리 | 역할 | 갱신 |
|---|---|---|---|
| `00_manual_override.sql` | 없음 | 수동 판정 목록. 데이터로 못 가리는 판단을 사람이 기록 | 판단이 생길 때 |
| `01_ext_table.sql` | 없음 (삭제) | 외부 테이블 생성/재생성 | 스키마 변경 시 |
| `02_raw_table.sql` | 없음 (삭제) | 네이티브 테이블 정의 | 컬럼 추가 시 |
| `03_merge_daily.sql` | (예약쿼리 `update_daily`) | 일별 MERGE 적재 + 로그. 백필 템플릿 포함 | 매일 23:00 KST 자동 |
| `04_view_derived.sql` | 없음 (삭제) | 히스토리 뷰 + 파생컬럼 | 파생 추가 시 |
| `05_view_latest.sql` | 없음 (삭제) | 회사별 최신 1행 뷰 | |
| `06_monthly_base.sql` | 없음 | 월말 기준일 x 회사. 월별 리포트의 토대 + 제외 사유 | |
| `07_view_by_snapshot_date.sql` | 없음 | 스냅샷 날짜별 뷰 | |
| `08_monthly_summary.sql` | 없음 | 월별 요약 (가입수·전환율·평균라이선스) | |
| `09_monthly_by_plan.sql` | 없음 | 월별 요금제 분포 (기업수·라이선스·평균) | |
| `50_run_log.sql` | `50_run_log` | 실행 로그 테이블 정의 | 최초 1회 |
| `51_run_merge_statement.sql` | `51_run_merge_statement` | MERGE 잡 7일치 모니터링 | 조회용 |
| `90_ext_table_check.sql` | `90_ext_table_check` | ext 테이블 특정 날짜 조회 | 수동 |
| `91_ext_column_check.sql` | `91_ext_column_check` | 하루치 parquet 1개의 컬럼·타입 확인 | 수동 |
| `92_view_table_check.sql` | `92_view_table_check` | 뷰/테이블 즉석 조회 (WHERE 예시 주석 모음) | 수동 |
| `93_table_list.sql` | `93_table_list` | 데이터셋의 테이블·뷰 목록 | 수동 |

### signup_2025/ — **미사용**

데이터셋이 2026-02 이후 갱신이 멈췄고 현재 쓰이지 않는다. 참고용 보관이며 실행하지 않는다.
`04_view_derived.sql`과 파생 구성이 어긋나 있으나 미사용이므로 맞추지 않는다.
다시 쓰게 되면 그때 04 기준으로 재작성한다.

| 파일 | 콘솔 저장쿼리 | 역할 | 최종 갱신 |
|---|---|---|---|
| `80_year_merge.sql` | 없음 (2026-09-01 삭제) | 연간 스냅샷 테이블 + 뷰 | 2026-02-12 |
| `81_year_detail_merge.sql` | 없음 (2026-09-01 삭제) | 상세 parquet → ext → raw → 뷰 | 2026-02-26 |

콘솔 저장쿼리는 지웠다. 선두 `DROP TABLE`을 무심코 실행할 여지를 없애기 위해서다.
내용은 이 파일들에 그대로 있으므로 다시 쓸 일이 생기면 복붙하면 된다.

소스 `signup_2025.signup_2025`(3,455행)는 2026-02-05에 한 번 적재된 일회성 수동
적재본이다. 이 저장소의 어떤 SQL도 그것을 만들지 않는다.

### search_console/ — **미배포 초안**

두 파일 모두 **전체가 주석으로 감싸여 있어 실행해도 아무 일도 일어나지 않는다.**
`carbiz-6f7fc.searchconsole` 데이터셋에는 원본 export 테이블만 있고 아래 `v_*` 뷰는
하나도 존재하지 않는다. 쓰려면 주석을 풀고 실행해야 한다.

| 파일 | 콘솔 저장쿼리 | 만들려는 뷰 |
|---|---|---|
| `02_create_view.sql` | `SearchConsole_02_create_view` | `v_page_daily`, `v_monthly_summary`, `v_yoy_monthly` |
| `03_dashboard_join_view.sql` | `SearchConsole_03_dashboard_join_view` | `v_dashboard_main` |

파일 주석에 남아 있는 핵심 원칙: **`query` dimension을 넣으면 클릭/노출이 과소집계된다.**
정확한 수치는 `query`를 빼고 집계해야 하며 `avg_position`은
`SAFE_DIVIDE(sum_position, impressions)`로 계산한다.

## 프로젝트의 다른 데이터셋

이 작업장은 `signup_90days` / `signup_2025` / `searchconsole`만 다룬다.
프로젝트에는 아래도 있으나 현재 범위 밖이다.

`analytics_429050434`, `analytics_528628070`, `analytics_528629362`, `ga4_mkt_analytics`

## 번호 체계

| 대역 | 용도 |
|---|---|
| `0x` | 파이프라인 본선 (ext → raw → merge → view) |
| `5x` | 운영·모니터링 (로그, 잡 조회) |
| `8x` | 연간 분석 |
| `9x` | 조회·점검 유틸 (파이프라인에 영향 없음) |

같은 단계의 변형은 `03b`처럼 접미 알파벳을 쓴다.
파일명은 ASCII만 쓴다. 공백·한글은 셸과 도구에서 깨진다.

## 실행 방법

```bash
# 문법·타입 검사 (실행 아님, 비용 0)
bq query --use_legacy_sql=false --dry_run < signup_90days/04_view_derived.sql

# 실제 배포
bq query --use_legacy_sql=false < signup_90days/04_view_derived.sql
```

뷰는 의존 순서대로 배포한다: `04` → `05` → `07` → `06`.
`04`를 먼저 올리지 않으면 하위 뷰가 컬럼을 못 찾아 실패한다.

## 주의

- **`02_raw_table.sql`은 통째로 실행하지 않는다.** 선두 `DROP TABLE`이 raw 누적
  스냅샷을 전량 삭제한다. 복구는 GCS 원본으로부터 전량 재머지뿐이다.
  `signup_2025/80_year_merge.sql`도 같다.
- **`03_merge_daily.sql`은 예약쿼리 실물의 사본이다.** 파일을 고쳐도 예약쿼리는
  바뀌지 않는다. 반영하려면 아래처럼 파일을 그대로 밀어넣는다. 콘솔 복붙보다
  안전하다 — 오타나 잘림이 원천 차단되고 바이트 단위로 일치한다.
  ```bash
  python3 - <<'EOF'
  import json, subprocess, io
  CFG = "projects/975350524805/locations/asia-northeast3/transferConfigs/697bce99-0000-2450-996f-089e082437ec"
  sql = io.open("signup_90days/03_merge_daily.sql", encoding="utf-8").read()
  # shell을 거치지 않는다. SQL 안의 백틱이 명령치환으로 해석되는 사고를 막는다.
  subprocess.run(["bq", "update", "--transfer_config",
                  f"--params={json.dumps({'query': sql})}", CFG], check=True)
  EOF
  ```
  스케줄·실패메일·서비스계정은 건드리지 않고 `params.query`만 바뀐다.
  운영 쿼리이므로 **반영 전에 새 쿼리 탭이나 `bq query`로 수동 1회 실행해 확인한다.**
  MERGE 키가 `(company_code, snapshot_date)`라 멱등하므로 같은 날 여러 번 돌려도 안전하다.
- **소급 적재(백필)는 `03_merge_daily.sql` 안의 주석 템플릿으로 한다.** 별도 파일을 두지
  않는다. 예전에 `03b_merge_backfill.sql`로 복제해 뒀더니 하루 만에 드리프트가 났다
  (`BEGIN`/`EXCEPTION` 개선이 한쪽에만 들어갔고 이력 주석도 갈라졌다).
  방법은 파일 선두 주석에 있다. 요약하면 콘솔 새 탭에 전문을 복사한 뒤
  `start_dt` 선언과 `WHERE dt BETWEEN` 줄의 주석을 풀고 실행한다.
  **예약쿼리 본문은 건드리지 않는다.**
  둘이 어긋나지 않았는지는 아래로 확인한다.
  ```bash
  bq show --format=prettyjson --transfer_config \
    projects/975350524805/locations/asia-northeast3/transferConfigs/697bce99-0000-2450-996f-089e082437ec \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['params']['query'])" \
    | diff - signup_90days/03_merge_daily.sql
  ```
- 유료/체험/무료 판정은 `04_view_derived.sql`의 `plan_status` **하나뿐이다.**
  하위 뷰에서 다시 정의하지 않는다.
- `contract_type_refine`은 계약기간 표현 전용이다. 유료 판정에 쓰지 않는다.
- **집계에서 라이선스를 셀 때는 `license_count_adjusted`를 쓴다.** 무료·체험 기업은
  라이선스가 100으로 기본 지급되므로 원본 `license_count`를 그대로 더하면 규모가 왜곡된다.
  무료·체험은 차량수로 대체하고 유료만 원값을 쓴다.
- **요금제 판정은 `plan_detail` 하나에서만 한다.** `plan_status`(free/trial/paid)와
  `is_paid_flag`는 거기서 파생된 값이다. 새 구분이 필요하면 `plan_detail`을 고친다.
- **회사명 정규화는 `NORMALIZE(NFKC)`를 먼저 건다.** 실제 데이터에 전각 괄호가 섞여
  있어(`（주）` 등 55건) 반각만 열거하면 그 회사들이 정규화에서 빠져나간다.
  NFKC가 전각→반각, `㈜`→`(주)`를 한 번에 처리한다.
- **`2026-07-29` 스냅샷은 소급 적재분이라 당시 상태가 아니다.** 원본이 2026-09-02에
  재생성됐다. 수집 원본은 가입 후 90일 이내 기업만 담으므로, 재생성 시점에 이미 90일이
  지난 기업은 이 파일에 들어있지 않다. 실제로 672행으로 인접일(7/28 745, 7/30 733)보다
  70여 건 적다. **그날의 전체 현황으로 읽으면 안 된다.**
  `07_view_by_snapshot`으로 `2026-07-29`를 조회할 때 특히 주의한다.
  월별 리포트는 월말(7/31) 스냅샷을 쓰므로 영향받지 않는다.
- **중복 판정 규칙은 `05` / `06` / `07`이 동일하다.** 유료 2개 이상이면 전체 유지,
  유료 1개면 유료와 실사용 무료 계정만 유지, 유료 0개면 활동량 1위만 유지한다.
  수동 판정이 그 위에 얹힌다. 한 곳만 고치지 않는다.
- **`company_name_norm`의 법인격 목록을 혼자 고치지 않는다.** 영업관리 시트(Apps Script)가
  같은 규칙을 자체 구현해 쓰고 있다. 한쪽만 바꾸면 두 시스템이 조용히 다른 답을 낸다.
  바꿔야 하면 **여기(`04_view_derived.sql`)에 먼저 반영하고 시트 쪽에 알린 뒤** 같은 회차에 맞춘다.
  2026-09-08 합의: `합자회사`는 양쪽 다 목록에 없다. 갈리는 것보다 같이 틀린 게 낫다는 판단이라
  넣지 않기로 했다. 넣으려면 위 순서를 지킨다.
- **자동 판정이 틀렸을 때는 `00_manual_override.sql`에 적는다.** 데이터만으로는 가릴 수
  없는 경우가 있다. 예를 들어 사내 테스트 계정이 실제로 운행 기록을 남기면 실사용 예외
  규칙에 걸려 살아남는다. 파일에 한 줄 넣고 그 파일만 실행하면 되며 뷰 재배포는 필요 없다.
  **반드시 `reason`을 적는다.** 근거 없는 수동 판정은 나중에 아무도 못 고친다.
- **`06_monthly_base`의 중복 판정은 `05`/`07`과 다르다.** 모집단이 "기준일 이하 전체
  기록에서 회사코드별 마지막 관측 행"이다. raw가 가입 후 90일까지만 쌓이므로,
  그 시점 스냅샷만 보면 같은 회사인데 일부 계정이 안 보인 채로 판정하게 되기 때문이다.
- **`license_count`의 GCS 원본 컬럼명은 `license_type`이다.** 이름이 타입처럼 보이지만
  실제 의미는 라이선스 개수다. 상류 parquet은 바꿀 수 없어 적재하면서 별칭을 준다
  (`03_merge_daily.sql`). raw 테이블부터는 `license_count`로만 존재한다.
- 파생컬럼은 `04_view_derived.sql`에서 한 번만 만든다. `05`/`07`은 상속만 받으며,
  둘에 남은 차이는 행 범위(`rn = 1` 여부)와 dedup `PARTITION`의 `snapshot_date`
  포함 여부 두 곳뿐이다. 한쪽만 고치지 않는다.

## 월별 리포트 뽑기

```sql
-- 표1: 월별 요약
SELECT * FROM `carbiz-6f7fc.signup_90days.view_signup_90days_monthly_summary`
ORDER BY ref_month DESC;

-- 표2: 월별 요금제 분포
SELECT * FROM `carbiz-6f7fc.signup_90days.view_signup_90days_monthly_by_plan`
WHERE ref_month = '2026-07';

-- 집계에서 제외된 기업 목록과 사유
SELECT ref_month, exclude_reason, company_code, company_name, company_name_norm,
       plan_detail, vehicle_count, user_count, trip_count_recent_2w,
       duplicate_company_count, paid_account_count, duplicate_keep_rank
FROM `carbiz-6f7fc.signup_90days.view_signup_90days_monthly_base`
WHERE ref_month = '2026-07' AND signup_year_month = ref_month
  AND exclude_reason IS NOT NULL
ORDER BY exclude_reason, company_name_norm, duplicate_keep_rank;
```

`exclude_reason`은 `test` / `withdrawn` / `manual` / `duplicate` 중 하나다.
`manual`은 사람이 `00_manual_override.sql`에 직접 적어 뺀 경우다.
수동으로 테스트 지정한 계정은 `test`로 찍힌다. 같은 이름 그룹이
나란히 나오므로 왜 빠졌는지 바로 보인다.

## 알아둘 객체

| 객체 | 내용 |
|---|---|
| `signup_90days._tmp_onefile_schema` | `91_ext_column_check.sql`이 매 실행마다 `CREATE OR REPLACE`로 다시 만드는 일회용 외부 테이블이다. 방치된 잔여물이 아니다. 지워도 그 쿼리를 다시 돌리면 살아난다. 외부 테이블이라 GCS 원본과 무관하다. |
| `92_view_table_check.sql` | `SELECT *`에 `LIMIT`이 없다. 그대로 돌리면 약 48MB를 스캔한다. 파일 안의 주석 처리된 `WHERE`/`LIMIT` 중 하나를 풀고 쓰는 것을 전제로 만든 쿼리다. |

## 관련 정책

- `CLAUDE.md` — 이 작업장의 BigQuery 실행 원칙
- `../policy/50_bigquery.md`, `../policy/10_naming.md`, `../policy/40_docs.md`
