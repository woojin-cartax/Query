-- 1. 기존 Table 삭제
DROP TABLE IF EXISTS `carbiz-6f7fc.signup_2025.raw_signup_2025`;

-- 2. 재생성 (스키마를 원본 데이터 타입에 맞춰 최적화)
CREATE OR REPLACE TABLE `carbiz-6f7fc.signup_2025.raw_signup_2025`
(
  snapshot_date DATE,
  data_collection_time DATETIME,
  sequence_id STRING,
  company_code STRING,
  company_name STRING,
  signup_date DATETIME,
  signup_device STRING,
  contract_type STRING,
  contract_period STRING,
  pricing_plan STRING,
  license_type INT64,
  is_booking_date DATETIME,
  user_count INT64,
  vehicle_count INT64,
  is_trial_active BOOL,
  has_app_login BOOL,
  pc_first_login_date DATETIME,
  pc_last_login_date DATETIME,
  first_trip_date_start DATETIME,
  first_trip_date_arrival DATETIME,
  last_trip_date_start DATETIME,
  last_trip_date_arrival DATETIME,
  trip_count_today INT64,
  trip_count_recent_2w INT64,
  trip_count_this_month INT64,
  trip_count_total INT64,
  first_trip_distance INT64,
  first_5_trips_distance INT64,
  last_trip_distance INT64,
  total_distance INT64,
  has_auto_trip_enabled BOOL,
  has_auto_trip_used BOOL,
  is_churned BOOL,
  has_sample_vehicle BOOL,
  has_sample_department BOOL,
  has_sample_position BOOL,
  updated_at TIMESTAMP
)
PARTITION BY snapshot_date
CLUSTER BY company_code;

-- 3. 데이터 병합
MERGE `carbiz-6f7fc.signup_2025.raw_signup_2025` T
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
    
    -- 타입별 맞춤 변환
    is_trial_active, -- 이미 BOOL이므로 그대로 사용
    has_app_login,
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
    
    -- Object(String) 타입 대응
    SAFE_CAST(first_trip_distance AS INT64) AS first_trip_distance,
    SAFE_CAST(first_5_trips_distance AS INT64) AS first_5_trips_distance,
    SAFE_CAST(last_trip_day_distance AS INT64) AS last_trip_distance,
    SAFE_CAST(total_distance AS INT64) AS total_distance,
    
    -- 나머지 FLOAT64 컬럼들을 BOOL로 변환
    has_auto_trip_enabled = 1.0 AS has_auto_trip_enabled,
    has_auto_trip_used = 1.0 AS has_auto_trip_used,
    is_churned = 1.0 AS is_churned,
    has_sample_vehicle = 1.0 AS has_sample_vehicle,
    has_sample_department = 1.0 AS has_sample_department,
    has_sample_position = 1.0 AS has_sample_position
  FROM `carbiz-6f7fc.signup_2025.signup_2025`
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


  CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_2025.view_signup_2025` AS

WITH base AS (
  SELECT
    r.*,

    /* 소스 추출 */
    CASE
      WHEN r.signup_device IS NULL OR TRIM(r.signup_device) = '' THEN NULL

      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'구글') THEN 'google'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'네이버_블로그') THEN 'naverblog'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'네이버웍스') THEN 'naverworks'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'네이버') THEN 'naver'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'카카오웰') THEN 'kakaowelcome'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'카카오') THEN 'kakao'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'다우오피스') THEN 'dowoffice'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'kt비즈오피스') THEN 'ktbizoffice'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'뉴스와이어') THEN 'newswire'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'깃북') THEN 'gitbook'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'나무위키') THEN 'namuwiki'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'유튜브') THEN 'youtube'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'페이스북') THEN 'facebook'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'chatgpt') THEN 'chatgpt'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'perplexity') THEN 'perplexity'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'ppss') THEN 'ppss'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'teams') THEN 'teams'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'빙') THEN 'bing'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'네이트') THEN 'nate'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'스티비') THEN 'stibe'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'티스토리') THEN 'tistory'

      -- AOS/iOS는 영문도 섞일 수 있어서 LOWER로 잡아둠
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'aos') THEN 'android'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'ios') THEN 'ios'

      -- 완전 일치 direct 처리(원본 수식과 동일)
      WHEN LOWER(TRIM(r.signup_device)) = 'direct' THEN 'direct'

      ELSE 'not_set'
    END AS signup_source,

    /* 채널 추출 */
    CASE
      WHEN r.signup_device IS NULL OR TRIM(r.signup_device) = '' THEN NULL

      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'자연검색') THEN 'organic'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'cpc') THEN 'cpc'

      -- referral 묶음 (AOS | iOS | 웍스 | 블로그)
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'aos|ios|웍스|블로그') THEN 'referral'

      -- social
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'페이스북|인스타|social') THEN 'social'

      -- 명시적 referral
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'referral') THEN 'referral'

      -- direct 완전일치
      WHEN LOWER(TRIM(r.signup_device)) = 'direct' THEN 'direct'

      ELSE 'not_set'
    END AS signup_channel,

    /* 키워드 추출 */
    CASE
      WHEN r.signup_device IS NULL OR TRIM(r.signup_device) = '' THEN NULL
      ELSE NULLIF(
        REGEXP_EXTRACT(
          r.signup_device,
          r'^[^_]+_[^_]+_[(]?([^\)_]+)[)]?$'
        ),
        ''
      )
    END AS signup_keyword,

    /* 가입 디바이스 */
    CASE
      WHEN r.signup_device IS NULL OR TRIM(r.signup_device) = '' THEN '알수없음'
      WHEN REGEXP_CONTAINS(r.signup_device, r'앱') THEN 'app'
      --WHEN REGEXP_CONTAINS(r.signup_device, r'Mobile') THEN 'mobile'
      --WHEN REGEXP_CONTAINS(r.signup_device, r'PC') THEN 'pc'
      ELSE 'pc'
    END AS signup_device_refine,

    /* 결제 수단 */
    CASE
      WHEN r.contract_type IS NULL OR TRIM(r.contract_type) = '' THEN NULL
      WHEN REGEXP_CONTAINS(r.contract_type, r'O') THEN 'subscribe'
      WHEN REGEXP_CONTAINS(r.contract_type, r'X') THEN 'unsubscribe'
      WHEN REGEXP_CONTAINS(r.contract_type, r'계좌') THEN 'transfer'
      ELSE NULL
    END AS subscribe_status,


    /* 1) 계약타입 : year, month, free, trial */
    CASE
      WHEN REGEXP_CONTAINS(r.contract_period, r'무료') THEN 'trial'
      WHEN REGEXP_CONTAINS(r.contract_period, r'12') THEN 'year'
      WHEN REGEXP_CONTAINS(r.contract_period, r'1') THEN 'month'
      WHEN r.contract_period IS NULL OR TRIM(r.contract_period) = '' THEN 'free'
      ELSE 'free'
    END AS contract_type_refine,


    /* 2) 초기 5회 평균 운행거리 */
    SAFE_DIVIDE(
      r.first_5_trips_distance, LEAST(r.trip_count_total, 5)) AS avg_distance_first_5_trips,

    /* 3) 운행 별 평균 운행거리 */
    SAFE_DIVIDE(r.total_distance, NULLIF(r.trip_count_total, 0)) AS avg_distance_per_trip,

    /* 3) 운행 별 평균 운행거리 */
    SAFE_DIVIDE(r.total_distance, NULLIF(r.user_count, 0)) AS avg_distance_per_user,

    /* 누적 운행거리 존재 여부 플래그 */
    IF(
      total_distance IS NOT NULL
      AND total_distance > 0,
      1, 0
    ) AS has_total_distance_flag,

    /* =========================
      last_trip_day_distance
      - (한글) "일간 운행거리" 목적의 값
      - 감소(음수)는 운행이 아니라 정정/삭제/수정일 가능성이 높아 0 처리 (어차피 변화랑 보려는 것이기 때문에)
    ========================= */
    CASE
      WHEN r.total_distance IS NULL THEN NULL
      WHEN LAG(r.total_distance) OVER (PARTITION BY r.company_code ORDER BY r.snapshot_date) IS NULL THEN NULL
      ELSE GREATEST(
        r.total_distance
        - LAG(r.total_distance) OVER (PARTITION BY r.company_code ORDER BY r.snapshot_date),
        0
      )
    END AS last_trip_day_distance,


    /* 4) 가입일부터 첫 운행까지 소요일 */
    CASE
      WHEN r.first_trip_date_start IS NULL OR r.signup_date IS NULL THEN NULL
      ELSE DATE_DIFF(DATE(r.first_trip_date_start), r.signup_date, DAY)
    END AS days_to_first_trip,

    /* 5) 가입일부터 첫 앱 로그인까지 소요일 (기준일 = snapshot_date, 최초 기준으로만) */
    MIN(r.signup_date) OVER (PARTITION BY r.company_code) AS signup_date_company,

    MIN(CASE WHEN r.has_app_login THEN r.snapshot_date END)
      OVER (PARTITION BY r.company_code) AS app_first_login_snapshot_date,

    CASE
      WHEN MIN(r.signup_date) OVER (PARTITION BY r.company_code) IS NULL
        OR MIN(CASE WHEN r.has_app_login THEN r.snapshot_date END)
            OVER (PARTITION BY r.company_code) IS NULL
      THEN NULL
      ELSE DATE_DIFF(
        MIN(CASE WHEN r.has_app_login THEN r.snapshot_date END)
          OVER (PARTITION BY r.company_code),
        MIN(r.signup_date) OVER (PARTITION BY r.company_code),
        DAY
      )
    END AS days_to_first_app_login,

    /* 5) 가입 후 경과일 (기준일 = snapshot_date) */
    CASE
      WHEN r.signup_date IS NULL THEN NULL
      ELSE DATE_DIFF(r.snapshot_date, r.signup_date, DAY)
    END AS days_since_signup,

    /* 6) 마지막 운행 후 경과일 */
    CASE
      WHEN r.last_trip_date_start IS NULL THEN NULL
      ELSE DATE_DIFF(r.snapshot_date, DATE(r.last_trip_date_start), DAY)
    END AS days_since_last_trip,

    /* 7) 마지막 관리자 접속 후 경과일 */
    CASE
      WHEN r.pc_last_login_date IS NULL THEN NULL
      ELSE DATE_DIFF(r.snapshot_date, DATE(r.pc_last_login_date), DAY)
    END AS days_since_last_pc_login,

    /* 10) 차량 수 세그먼트 (코드값) 
    CASE
      WHEN r.vehicle_count IS NULL THEN NULL
      WHEN r.vehicle_count = 0 THEN 0
      WHEN r.vehicle_count = 1 THEN 1
      WHEN r.vehicle_count BETWEEN 2 AND 3 THEN 2
      WHEN r.vehicle_count BETWEEN 4 AND 9 THEN 3
      ELSE 4
    END AS vehicle_segment,

    /* 11) 사용자 수 세그먼트 (코드값) 
    CASE
      WHEN r.user_count IS NULL THEN NULL
      WHEN r.user_count = 0 THEN 0
      WHEN r.user_count = 1 THEN 1
      WHEN r.user_count BETWEEN 2 AND 5 THEN 2
      WHEN r.user_count BETWEEN 6 AND 20 THEN 3
      ELSE 4
    END AS user_segment,

    /* 12) 운행 수 세그먼트 (코드값) 
    CASE
      WHEN r.trip_count_total IS NULL THEN NULL
      WHEN r.trip_count_total = 0 THEN 0
      WHEN r.trip_count_total = 1 THEN 1
      WHEN r.trip_count_total BETWEEN 2 AND 5 THEN 2
      WHEN r.trip_count_total BETWEEN 6 AND 20 THEN 3
      ELSE 4
    END AS trip_count_segment,

    /* 13) 누적 운행거리 세그먼트 (코드값) 
    CASE
      WHEN r.total_distance IS NULL THEN NULL
      WHEN r.total_distance = 0 THEN 0
      WHEN r.total_distance BETWEEN 1 AND 30 THEN 1
      WHEN r.total_distance BETWEEN 31 AND 200 THEN 2
      WHEN r.total_distance BETWEEN 201 AND 1000 THEN 3
      ELSE 4
    END AS trip_distance_segment,
    */

    -- 🔹 Looker SUM용 0/1 플래그
    IFNULL(CAST(is_trial_active AS INT64), 0) AS is_trial_active_flag,
    IFNULL(CAST(has_app_login AS INT64), 0) AS has_app_login_flag,

    /* 14) 테스트 계정 여부 (분석 제외용) */
    REGEXP_CONTAINS(
      CONCAT(IFNULL(r.company_name,''), ' ', IFNULL(r.company_code,'')),
      r'(영티포|카택스|테스트|4424)'
    ) AS is_test_account,

    /* 15) 업체관리 페이지 링크 (예시 템플릿) */
    CONCAT('https://cds.carbeast.co.kr/admin/companyManager.php?service=biz&seq=', r.sequence_id) AS company_admin_url,

    /* =========================
      Looker SUM용 기본 FLAG (0/1)
      - (한글) 히스토리 뷰에서 기본 flag를 표준화해두면 latest에서 재사용이 쉬움
    ========================= */

    /* (한글) 첫 운행 발생 여부 */
    IF(first_trip_date_start IS NOT NULL, 1, 0) AS has_first_trip_flag,

    /* (한글) 반복 운행 여부(누적 2회 이상) */
    IF(trip_count_total >= 2, 1, 0) AS is_repeat_trip_flag,

  FROM `carbiz-6f7fc.signup_2025.raw_signup_2025` r
),

final AS (
  SELECT
    base.*,

  FROM base
)

SELECT * FROM final;
