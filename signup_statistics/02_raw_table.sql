/* ============================================================================
   02. Native Table — 실제 데이터를 저장한다
   ----------------------------------------------------------------------------
   ※ 이 파일을 통째로 실행하지 않는다. 선두가 DROP TABLE 이다.
     raw 는 일별 누적 스냅샷이고, GCS 원본으로부터 전량 재머지해야 복구된다.

   signup_90days 와 컬럼 34개가 공통이다. 차이 셋.

   | | |
   |---|---|
   | `corporate_number` | **사업자등록번호. 여기만 있다.** 중복 판정을 근본적으로 바꾼다 |
   | `license_type` | 90일에서 `license_count` 로 바로잡은 그 오기. 여기서도 바로잡는다 |
   | `updated_at` 없음 | 증분 적재 기준이 없다. 매일 전량 받아 날짜별로 쌓는다 |

   세 번째가 적재 방식을 정한다. MERGE 키는 (snapshot_date, company_code) 이고
   그것만으로 멱등하다 — 날짜가 파티션이라 같은 날짜를 다시 받으면 덮어쓴다.
   `updated_at` 비교가 필요 없다.

   parquet 의 날짜·시각이 전부 STRING 이라 적재하면서 변환한다.
   ========================================================================= */

DROP TABLE IF EXISTS `carbiz-6f7fc.signup_statistics.raw_signup_statistics`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.signup_statistics.raw_signup_statistics`
(
  snapshot_date             DATE,
  data_collection_time      DATETIME,   -- 전 행 동일. 22:00:02 (KST)
  sequence_id               STRING,
  company_code              STRING,
  company_name              STRING,
  corporate_number          STRING,     -- ★ 90일 피드에 없다
  signup_date               DATETIME,
  signup_device             STRING,     -- 유입 경로 문장이 들어온다. 일부 비어 있음
  contract_type             STRING,
  contract_period           STRING,
  pricing_plan              STRING,
  license_count             INT64,      -- parquet 원본명은 license_type. 적재 시 교정
  is_booking_date           DATETIME,
  user_count                INT64,
  vehicle_count             INT64,
  is_trial_active           BOOL,
  has_app_login             BOOL,
  pc_first_login_date       DATETIME,
  pc_last_login_date        DATETIME,
  first_trip_date_start     DATETIME,
  first_trip_date_arrival   DATETIME,
  last_trip_date_start      DATETIME,
  last_trip_date_arrival    DATETIME,
  trip_count_today          INT64,      -- ※ 상시 약 −1.1%. 아래 주석 참조
  trip_count_recent_2w      INT64,
  trip_count_this_month     INT64,
  trip_count_total          INT64,
  first_trip_distance       INT64,
  first_5_trips_distance    INT64,
  last_trip_day_distance    INT64,      -- 90일의 last_trip_distance 와 같은 것
  total_distance            INT64,
  has_auto_trip_enabled     INT64,
  has_auto_trip_used        INT64,
  is_churned                INT64,
  has_sample_vehicle        INT64,
  has_sample_department     INT64,
  has_sample_position       INT64,
  loaded_at                 TIMESTAMP
)
PARTITION BY snapshot_date
CLUSTER BY company_code
OPTIONS (
  description = '전 고객사 일별 집계 스냅샷. gs://cartax-biz-statistics/. 90일 피드와 34컬럼 공통이고 corporate_number 가 추가됐다. updated_at 이 없어 증분이 아니라 날짜별 전량이다.'
);

/* ── trip_count_today 를 일별 추이에 쓰지 않는다 ─────────────────────────
   수집이 매일 22:00(KST)에 돌아서 22:00~24:00 운행은 **어느 날의
   trip_count_today 에도 들어가지 않는다.** 그날은 집계 후라서, 다음 날은
   운행일이 어제라서. 영구 누락이다.

   90일 피드에서 실측했다 (2026-09-27~30, 20,537개사):
     trip_count_total 증가  82,189
     trip_count_today 합    81,262
     차이                      927  = 1.1%, 하루 약 309건

   같은 측정에서 누적 운행수가 줄어든 기업은 0건이었다.
   일별 운행 추이가 필요하면 trip_count_total 차분을 쓴다.
   ------------------------------------------------------------------------ */
