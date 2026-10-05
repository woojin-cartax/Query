/* ============================================================================
   03. 일별 적재 — 예약 쿼리 본문
   ----------------------------------------------------------------------------
   MERGE 키가 (snapshot_date, company_code) 라 멱등하다. 여러 번 돌려도 안전하다.
   이 피드에는 updated_at 이 없어서 「더 새로운 행만 갱신」 비교를 하지 않는다 —
   같은 날짜를 다시 받으면 그 날짜를 통째로 덮어쓰는 것이 맞다.

   [소급 적재] 아래 두 줄의 주석을 바꿔 단다. 파일을 복제하지 않는다.
     기본    target_dt 하루
     소급    start_dt ~ target_dt 범위

   ※ 무증상 실패를 전제로 만든다. 성공했다는 기록만으로는 파이프라인이 살아 있다는
     증거가 되지 않는다. 행이 0이면 EMPTY 로 남긴다.
   ========================================================================= */

DECLARE target_dt DATE DEFAULT DATE_SUB(CURRENT_DATE("Asia/Seoul"), INTERVAL 1 DAY);
--DECLARE start_dt  DATE DEFAULT DATE('2026-09-15');   -- 소급 적재용 (주석 해제)

DECLARE before_cnt, after_cnt, merged_cnt INT64;

BEGIN

  SET before_cnt = (
    SELECT COUNT(*) FROM `carbiz-6f7fc.signup_statistics.raw_signup_statistics`
    WHERE snapshot_date = target_dt);
  --WHERE snapshot_date BETWEEN start_dt AND target_dt);   -- 소급용

  MERGE `carbiz-6f7fc.signup_statistics.raw_signup_statistics` T
  USING (
    SELECT
      CAST(snapshot_date AS DATE)                                        AS snapshot_date,
      SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', data_collection_time)     AS data_collection_time,
      CAST(sequence_id AS STRING)                                        AS sequence_id,
      CAST(company_code AS STRING)                                       AS company_code,
      CAST(company_name AS STRING)                                       AS company_name,
      /* 사업자등록번호. 90일 피드에 없던 컬럼이다. 하이픈 표기가 섞여 올 수 있으나
         정규화는 뷰에서 한다 — 적재는 원본 그대로 둔다 */
      CAST(corporate_number AS STRING)                                   AS corporate_number,
      SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', signup_date)              AS signup_date,
      CAST(signup_device AS STRING)                                      AS signup_device,
      CAST(contract_type AS STRING)                                      AS contract_type,
      CAST(contract_period AS STRING)                                    AS contract_period,
      CAST(pricing_plan AS STRING)                                       AS pricing_plan,
      /* parquet 원본명은 license_type 이지만 실제 의미는 라이선스 '개수'다.
         상류를 바꿀 수 없으므로 적재하면서 이름을 바로잡는다.
         signup_90days 와 같은 교정이다 — 두 피드의 같은 값이 다른 이름이면 안 된다 */
      CAST(license_type AS INT64)                                        AS license_count,
      SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', is_booking_date)          AS is_booking_date,
      CAST(user_count AS INT64)                                          AS user_count,
      CAST(vehicle_count AS INT64)                                       AS vehicle_count,
      CAST(is_trial_active AS BOOL)                                      AS is_trial_active,
      CAST(has_app_login AS BOOL)                                        AS has_app_login,
      SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', pc_first_login_date)      AS pc_first_login_date,
      SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', pc_last_login_date)       AS pc_last_login_date,
      SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', first_trip_date_start)    AS first_trip_date_start,
      SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', first_trip_date_arrival)  AS first_trip_date_arrival,
      SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', last_trip_date_start)     AS last_trip_date_start,
      SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', last_trip_date_arrival)   AS last_trip_date_arrival,
      CAST(trip_count_today AS INT64)                                    AS trip_count_today,
      CAST(trip_count_recent_2w AS INT64)                                AS trip_count_recent_2w,
      CAST(trip_count_this_month AS INT64)                               AS trip_count_this_month,
      CAST(trip_count_total AS INT64)                                    AS trip_count_total,
      CAST(first_trip_distance AS INT64)                                 AS first_trip_distance,
      CAST(first_5_trips_distance AS INT64)                              AS first_5_trips_distance,
      CAST(last_trip_day_distance AS INT64)                              AS last_trip_day_distance,
      CAST(total_distance AS INT64)                                      AS total_distance,
      CAST(has_auto_trip_enabled AS INT64)                               AS has_auto_trip_enabled,
      CAST(has_auto_trip_used AS INT64)                                  AS has_auto_trip_used,
      CAST(is_churned AS INT64)                                          AS is_churned,
      CAST(has_sample_vehicle AS INT64)                                  AS has_sample_vehicle,
      CAST(has_sample_department AS INT64)                               AS has_sample_department,
      CAST(has_sample_position AS INT64)                                 AS has_sample_position,
      CURRENT_TIMESTAMP()                                                AS loaded_at
    FROM `carbiz-6f7fc.signup_statistics.ext_signup_statistics`
    WHERE dt = target_dt
    --WHERE dt BETWEEN start_dt AND target_dt   -- 소급용
  ) S
  ON  T.snapshot_date = S.snapshot_date
  AND T.company_code  = S.company_code
  WHEN MATCHED THEN UPDATE SET
    data_collection_time = S.data_collection_time, sequence_id = S.sequence_id,
    company_name = S.company_name, corporate_number = S.corporate_number,
    signup_date = S.signup_date, signup_device = S.signup_device,
    contract_type = S.contract_type, contract_period = S.contract_period,
    pricing_plan = S.pricing_plan, license_count = S.license_count,
    is_booking_date = S.is_booking_date, user_count = S.user_count,
    vehicle_count = S.vehicle_count, is_trial_active = S.is_trial_active,
    has_app_login = S.has_app_login, pc_first_login_date = S.pc_first_login_date,
    pc_last_login_date = S.pc_last_login_date,
    first_trip_date_start = S.first_trip_date_start,
    first_trip_date_arrival = S.first_trip_date_arrival,
    last_trip_date_start = S.last_trip_date_start,
    last_trip_date_arrival = S.last_trip_date_arrival,
    trip_count_today = S.trip_count_today,
    trip_count_recent_2w = S.trip_count_recent_2w,
    trip_count_this_month = S.trip_count_this_month,
    trip_count_total = S.trip_count_total,
    first_trip_distance = S.first_trip_distance,
    first_5_trips_distance = S.first_5_trips_distance,
    last_trip_day_distance = S.last_trip_day_distance,
    total_distance = S.total_distance,
    has_auto_trip_enabled = S.has_auto_trip_enabled,
    has_auto_trip_used = S.has_auto_trip_used, is_churned = S.is_churned,
    has_sample_vehicle = S.has_sample_vehicle,
    has_sample_department = S.has_sample_department,
    has_sample_position = S.has_sample_position,
    loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET merged_cnt = @@row_count;

  SET after_cnt = (
    SELECT COUNT(*) FROM `carbiz-6f7fc.signup_statistics.raw_signup_statistics`
    WHERE snapshot_date = target_dt);
  --WHERE snapshot_date BETWEEN start_dt AND target_dt);   -- 소급용

  INSERT INTO `carbiz-6f7fc.signup_statistics.query_run_log`
  VALUES (target_dt, 'signup_statistics_daily', 'raw_signup_statistics',
          IF(after_cnt = 0, 'EMPTY', 'SUCCESS'),
          after_cnt - before_cnt,
          merged_cnt - (after_cnt - before_cnt),
          CAST(NULL AS STRING), CURRENT_TIMESTAMP());

EXCEPTION WHEN ERROR THEN
  INSERT INTO `carbiz-6f7fc.signup_statistics.query_run_log`
  VALUES (target_dt, 'signup_statistics_daily', 'raw_signup_statistics', 'FAIL',
          CAST(NULL AS INT64), CAST(NULL AS INT64),
          @@error.message, CURRENT_TIMESTAMP());
  RAISE USING MESSAGE = @@error.message;
END;
