-- 테이블 생성
-- 분석에 필요한 컬럼 파싱하는 작업이 이곳에서 이뤄짐
-- 생성되거나 원하는 컬럼만 추가하거나
-- 이 작업 진행 후에는 update 새로 진행해 줘야함
-- 특히 컬럼명 변경 등 진행될 경우에..
-- 가능하면 컬럼명 변경은 진행하지 않는 것 추천

-- 1. 기존 Table 삭제
DROP TABLE IF EXISTS `carbiz-6f7fc.signup_90days.raw_signup_90days`;

-- 2. 재생성
CREATE OR REPLACE TABLE `carbiz-6f7fc.signup_90days.raw_signup_90days`
--CREATE OR REPLACE TABLE `carbiz-6f7fc.signup_2025.raw_signup_2025`
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
  license_count INT64,     -- GCS parquet 원본 컬럼명은 license_type. 적재 시 별칭을 준다.
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
