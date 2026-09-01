/*
====================================
>> info
====================================
- 데이터 최초 수집일 2026.01.26
- 컬럼 정의서 확인 https://docs.google.com/spreadsheets/d/1cFeuBuFb_Cuck1gmYMhRFtxewbRqd9gTwBg-YiOOC9I/edit?gid=445051683#gid=445051683


====================================



====================================
History
====================================
- ver1.0 20260112 컬럼 1차 확정 @전우진
- ver1.2 20260901 BEGIN/EXCEPTION 도입. 실패해도 FAIL 행이 남고 실패 메일이 온다.
                  updated_rows 채움. 적재 0행은 EMPTY로 구분.


====================================
*/


DECLARE target_dt DATE DEFAULT DATE_SUB(CURRENT_DATE("Asia/Seoul"), INTERVAL 0 DAY);
DECLARE before_cnt INT64;
DECLARE after_cnt INT64;
DECLARE merged_cnt INT64;

/* 아래 전체를 감싼다. 어느 단계에서 실패하든 EXCEPTION 절이 FAIL 행을 남긴 뒤
   오류를 재발생시킨다. 재발생시키지 않으면 예약쿼리가 "성공"으로 끝나 실패 메일이
   오지 않는다. BigQuery 스크립트는 문장 단위로 커밋되므로 RAISE 이전에 넣은
   INSERT는 살아남는다. */
BEGIN

-- 1️⃣ 실행 전 row 수
SET before_cnt = (
  SELECT COUNT(*)
  FROM `carbiz-6f7fc.signup_90days.raw_signup_90days`
  WHERE snapshot_date = target_dt
);

-- 2️⃣ MERGE 실행
MERGE `carbiz-6f7fc.signup_90days.raw_signup_90days` T

USING (
  SELECT
    CAST(snapshot_date AS DATE) AS snapshot_date,
    SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', data_collection_time) AS data_collection_time,
    CAST(sequence_id AS STRING) AS sequence_id,
    CAST(company_code AS STRING) AS company_code,
    CAST(company_name AS STRING) AS company_name,
    SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', signup_date) AS signup_date,
    CAST(signup_device AS STRING) AS signup_device,
    CAST(contract_type AS STRING) AS contract_type,
    CAST(contract_period AS STRING) AS contract_period,
    CAST(pricing_plan AS STRING) AS pricing_plan,
    CAST(license_type AS INT64) AS license_type,
    SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', is_booking_date) AS is_booking_date,
    CAST(user_count AS INT64) AS user_count,
    CAST(vehicle_count AS INT64) AS vehicle_count,
    CAST(is_trial_active AS BOOL) AS is_trial_active,
    CAST(has_app_login AS BOOL) AS has_app_login,
    SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', pc_first_login_date) AS pc_first_login_date,
    SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', pc_last_login_date) AS pc_last_login_date,
    SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', first_trip_date_start) AS first_trip_date_start,
    SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', first_trip_date_arrival) AS first_trip_date_arrival,
    SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', last_trip_date_start) AS last_trip_date_start,
    SAFE.PARSE_DATETIME('%Y-%m-%d %H:%M:%S', last_trip_date_arrival) AS last_trip_date_arrival,
    CAST(trip_count_today AS INT64) AS trip_count_today,
    CAST(trip_count_recent_2w AS INT64) AS trip_count_recent_2w,
    CAST(trip_count_this_month AS INT64) AS trip_count_this_month,
    CAST(trip_count_total AS INT64) AS trip_count_total,
    CAST(first_trip_distance AS INT64) AS first_trip_distance,
    CAST(first_5_trips_distance AS INT64) AS first_5_trips_distance,
    CAST(last_trip_day_distance AS INT64) AS last_trip_distance,
    CAST(total_distance AS INT64) AS total_distance,
    CAST(has_auto_trip_enabled AS BOOL) AS has_auto_trip_enabled,
    CAST(has_auto_trip_used AS BOOL) AS has_auto_trip_used,
    CAST(is_churned AS BOOL) AS is_churned,
    CAST(has_sample_vehicle AS BOOL) AS has_sample_vehicle,
    CAST(has_sample_department AS BOOL) AS has_sample_department,
    CAST(has_sample_position AS BOOL) AS has_sample_position
  FROM `carbiz-6f7fc.signup_90days.ext_signup_90days`
  WHERE dt = target_dt
) S
ON T.company_code = S.company_code
AND T.snapshot_date = S.snapshot_date
WHEN MATCHED THEN
  UPDATE SET
    T.data_collection_time = S.data_collection_time,
    T.sequence_id = S.sequence_id,
    T.company_name = S.company_name,
    T.signup_date = S.signup_date,
    T.signup_device = S.signup_device,
    T.contract_type = S.contract_type,
    T.contract_period = S.contract_period,
    T.pricing_plan = S.pricing_plan,
    T.license_type = S.license_type,
    T.is_booking_date = S.is_booking_date,
    T.user_count = S.user_count,
    T.vehicle_count = S.vehicle_count,
    T.is_trial_active = S.is_trial_active,
    T.has_app_login = S.has_app_login,
    T.pc_first_login_date = S.pc_first_login_date,
    T.pc_last_login_date = S.pc_last_login_date,
    T.first_trip_date_start = S.first_trip_date_start,
    T.first_trip_date_arrival = S.first_trip_date_arrival,
    T.last_trip_date_start = S.last_trip_date_start,
    T.last_trip_date_arrival = S.last_trip_date_arrival,
    T.trip_count_today = S.trip_count_today,
    T.trip_count_recent_2w = S.trip_count_recent_2w,
    T.trip_count_this_month = S.trip_count_this_month,
    T.trip_count_total = S.trip_count_total,
    T.first_trip_distance = S.first_trip_distance,
    T.first_5_trips_distance = S.first_5_trips_distance,
    T.last_trip_distance = S.last_trip_distance,
    T.total_distance = S.total_distance,
    T.has_auto_trip_enabled = S.has_auto_trip_enabled,
    T.has_auto_trip_used = S.has_auto_trip_used,
    T.is_churned = S.is_churned,
    T.has_sample_vehicle = S.has_sample_vehicle,
    T.has_sample_department = S.has_sample_department,
    T.has_sample_position = S.has_sample_position,
    T.updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
  INSERT (
    snapshot_date, data_collection_time, sequence_id,
    company_code, company_name,
    signup_date, signup_device, contract_type, contract_period, pricing_plan, license_type,
    is_booking_date, user_count, vehicle_count,
    is_trial_active, has_app_login,
    pc_first_login_date, pc_last_login_date,
    first_trip_date_start, first_trip_date_arrival,
    last_trip_date_start, last_trip_date_arrival,
    trip_count_today, trip_count_recent_2w, trip_count_this_month, trip_count_total,
    first_trip_distance, first_5_trips_distance, last_trip_distance, total_distance,
    has_auto_trip_enabled, has_auto_trip_used,
    is_churned, has_sample_vehicle, has_sample_department, has_sample_position,
    updated_at
  )
  VALUES (
    S.snapshot_date, S.data_collection_time, S.sequence_id,
    S.company_code, S.company_name,
    S.signup_date, S.signup_device, S.contract_type, S.contract_period, S.pricing_plan, S.license_type,
    S.is_booking_date, S.user_count, S.vehicle_count,
    S.is_trial_active, S.has_app_login,
    S.pc_first_login_date, S.pc_last_login_date,
    S.first_trip_date_start, S.first_trip_date_arrival,
    S.last_trip_date_start, S.last_trip_date_arrival,
    S.trip_count_today, S.trip_count_recent_2w, S.trip_count_this_month, S.trip_count_total,
    S.first_trip_distance, S.first_5_trips_distance, S.last_trip_distance, S.total_distance,
    S.has_auto_trip_enabled, S.has_auto_trip_used,
    S.is_churned, S.has_sample_vehicle, S.has_sample_department, S.has_sample_position,
    CURRENT_TIMESTAMP()
  );

-- MERGE가 건드린 총 행수 (INSERT + UPDATE). 반드시 MERGE 바로 다음에 읽어야 한다.
SET merged_cnt = @@row_count;

-- 3️⃣ 실행 후 row 수
SET after_cnt = (
  SELECT COUNT(*)
  FROM `carbiz-6f7fc.signup_90days.raw_signup_90days`
  WHERE snapshot_date = target_dt
);

-- 4️⃣ 로그 남기기
--    status      : 적재 결과가 0행이면 EMPTY. GCS에 원본이 안 올라온 날을 구분한다.
--    inserted_rows: 신규 행수 (순증분)
--    updated_rows : MERGE가 갱신한 행수 = 총 영향 행수 - 신규 행수
INSERT INTO `carbiz-6f7fc.signup_90days.query_run_log`
VALUES (
  target_dt,
  'daily_signup_merge',
  'raw_signup_90days',
  IF(after_cnt = 0, 'EMPTY', 'SUCCESS'),
  after_cnt - before_cnt,
  merged_cnt - (after_cnt - before_cnt),
  NULL,
  CURRENT_TIMESTAMP()
);

EXCEPTION WHEN ERROR THEN
  -- 실패 흔적을 남긴 뒤 오류를 그대로 재발생시킨다.
  INSERT INTO `carbiz-6f7fc.signup_90days.query_run_log`
  VALUES (
    target_dt,
    'daily_signup_merge',
    'raw_signup_90days',
    'FAIL',
    NULL,
    NULL,
    @@error.message,
    CURRENT_TIMESTAMP()
  );
  RAISE USING MESSAGE = @@error.message;
END;