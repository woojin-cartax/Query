/* =========================
   [미사용] 2026-09-01 기준

   signup_2025 데이터셋은 2026-02 이후 갱신이 멈췄고 현재 쓰이지 않는다.
   이 파일은 참고용 보관이다. 실행하지 않는다.
   파생컬럼 없이 SAFE_CAST로 타입만 고정하는 뷰다.
========================= */

-- =========================
-- 1) External Table (GCS parquet 연결)
-- =========================
CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.signup_2025.ext_signup_detail_2025_v1`
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://cartax-biz_signup_year/signup_2025_detail/signup_detail_2025_master_db.parquet']
);

-- =========================
-- 2) RAW 물리 테이블로 적재 (BigQuery 내부 저장)
-- =========================
CREATE OR REPLACE TABLE `carbiz-6f7fc.signup_2025.raw_signup_detail_2025_v1` AS
SELECT *
FROM `carbiz-6f7fc.signup_2025.ext_signup_detail_2025_v1`;

-- =========================
-- 3) 대시보드용 VIEW (타입 고정: SAFE_CAST)
--    *파생컬럼 없음 / 컬럼 그대로 + 타입만 고정*
-- =========================
CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_2025.view_signup_detail_2025_v1` AS
SELECT
  SAFE_CAST(signup_date AS TIMESTAMP) AS signup_date,
  SAFE_CAST(sequence_id AS INT64) AS sequence_id,
  SAFE_CAST(company_code AS STRING) AS company_code,
  SAFE_CAST(pc_login_count_total AS INT64) AS pc_login_count_total,
  SAFE_CAST(first_payment_date AS TIMESTAMP) AS first_payment_date,
  SAFE_CAST(first_contract_period AS STRING) AS first_contract_period,
  SAFE_CAST(first_pricing_plan AS STRING) AS first_pricing_plan,
  SAFE_CAST(first_payment_method AS STRING) AS first_payment_method,
  SAFE_CAST(first_license_count AS FLOAT64) AS first_license_count,
  SAFE_CAST(first_user_count AS FLOAT64) AS first_user_count,
  SAFE_CAST(first_vehicle_count AS FLOAT64) AS first_vehicle_count,
  SAFE_CAST(first_trip_distance AS FLOAT64) AS first_trip_distance,
  SAFE_CAST(first_trip_count AS FLOAT64) AS first_trip_count,
  SAFE_CAST(first_has_auto_trip_enabled AS STRING) AS first_has_auto_trip_enabled,
  SAFE_CAST(first_auto_trip_distance AS FLOAT64) AS first_auto_trip_distance,
  SAFE_CAST(last_payment_date AS TIMESTAMP) AS last_payment_date,
  SAFE_CAST(last_contract_period AS STRING) AS last_contract_period,
  SAFE_CAST(last_pricing_plan AS STRING) AS last_pricing_plan,
  SAFE_CAST(last_payment_method AS STRING) AS last_payment_method,
  SAFE_CAST(last_license_count AS FLOAT64) AS last_license_count,
  SAFE_CAST(last_user_count AS FLOAT64) AS last_user_count,
  SAFE_CAST(last_vehicle_count AS FLOAT64) AS last_vehicle_count,
  SAFE_CAST(last_trip_distance AS FLOAT64) AS last_trip_distance,
  SAFE_CAST(last_trip_count AS FLOAT64) AS last_trip_count,
  SAFE_CAST(payment_count_total AS INT64) AS payment_count_total,
  SAFE_CAST(refund_count_total AS INT64) AS refund_count_total,
  SAFE_CAST(last_refund_date AS TIMESTAMP) AS last_refund_date,
  SAFE_CAST(is_booking_date AS TIMESTAMP) AS is_booking_date,
  SAFE_CAST(is_booking_cancel_date AS TIMESTAMP) AS is_booking_cancel_date,
  SAFE_CAST(admin_first_trip_date AS TIMESTAMP) AS admin_first_trip_date,
  SAFE_CAST(admin_first_trip_distance AS FLOAT64) AS admin_first_trip_distance,
  SAFE_CAST(admin_first_gps_trip_distance AS FLOAT64) AS admin_first_gps_trip_distance,
  SAFE_CAST(admin_first_nonzero_trip_date AS TIMESTAMP) AS admin_first_nonzero_trip_date,
  SAFE_CAST(admin_first_nonzero_trip_distance AS FLOAT64) AS admin_first_nonzero_trip_distance,
  SAFE_CAST(admin_first_nonzero_gps_trip_distance AS FLOAT64) AS admin_first_nonzero_gps_trip_distance,
  SAFE_CAST(admin_last_trip_date AS TIMESTAMP) AS admin_last_trip_date,
  SAFE_CAST(admin_last_trip_distance AS FLOAT64) AS admin_last_trip_distance,
  SAFE_CAST(member_first_trip_date AS TIMESTAMP) AS member_first_trip_date,
  SAFE_CAST(member_first_trip_distance AS FLOAT64) AS member_first_trip_distance,
  SAFE_CAST(member_first_gps_trip_distance AS FLOAT64) AS member_first_gps_trip_distance,
  SAFE_CAST(member_first_nonzero_trip_date AS TIMESTAMP) AS member_first_nonzero_trip_date,
  SAFE_CAST(member_first_nonzero_trip_distance AS FLOAT64) AS member_first_nonzero_trip_distance,
  SAFE_CAST(member_first_nonzero_gps_trip_distance AS FLOAT64) AS member_first_nonzero_gps_trip_distance,
  SAFE_CAST(member_last_trip_date AS TIMESTAMP) AS member_last_trip_date,
  SAFE_CAST(member_last_trip_distance AS FLOAT64) AS member_last_trip_distance,
  SAFE_CAST(admin_has_auto_trip_used AS BOOL) AS admin_has_auto_trip_used,
  SAFE_CAST(admin_auto_trip_date AS TIMESTAMP) AS admin_auto_trip_date,
  SAFE_CAST(admin_auto_trip_distance AS FLOAT64) AS admin_auto_trip_distance,
  SAFE_CAST(admin_auto_nonzero_trip_date AS TIMESTAMP) AS admin_auto_nonzero_trip_date,
  SAFE_CAST(admin_auto_nonzero_trip_distance AS FLOAT64) AS admin_auto_nonzero_trip_distance,
  SAFE_CAST(member_has_auto_trip_used AS BOOL) AS member_has_auto_trip_used,
  SAFE_CAST(member_auto_trip_date AS TIMESTAMP) AS member_auto_trip_date,
  SAFE_CAST(member_auto_trip_distance AS FLOAT64) AS member_auto_trip_distance,
  SAFE_CAST(member_auto_nonzero_trip_date AS TIMESTAMP) AS member_auto_nonzero_trip_date,
  SAFE_CAST(member_auto_nonzero_trip_distance AS FLOAT64) AS member_auto_nonzero_trip_distance,
  SAFE_CAST(acquisition_channel AS STRING) AS acquisition_channel,
  SAFE_CAST(acquisition_channel_clean AS STRING) AS acquisition_channel_clean,
  SAFE_CAST(channel_group AS STRING) AS channel_group,
  SAFE_CAST(days_since_signup AS INT64) AS days_since_signup,
  SAFE_CAST(signup_weekday AS STRING) AS signup_weekday,
  SAFE_CAST(signup_weekday_kr AS STRING) AS signup_weekday_kr,
  SAFE_CAST(signup_hour AS INT64) AS signup_hour,
  SAFE_CAST(signup_period AS STRING) AS signup_period,
  SAFE_CAST(signup_year_month AS STRING) AS signup_year_month,
  SAFE_CAST(is_paid_company AS INT64) AS is_paid_company,
  SAFE_CAST(days_to_first_payment AS FLOAT64) AS days_to_first_payment,
  SAFE_CAST(contract_months AS INT64) AS contract_months,
  SAFE_CAST(pricing_tier AS INT64) AS pricing_tier,
  SAFE_CAST(days_to_refund AS FLOAT64) AS days_to_refund,
  SAFE_CAST(admin_has_trip AS INT64) AS admin_has_trip,
  SAFE_CAST(admin_has_real_trip AS INT64) AS admin_has_real_trip,
  SAFE_CAST(member_has_trip AS INT64) AS member_has_trip,
  SAFE_CAST(member_has_real_trip AS INT64) AS member_has_real_trip,
  SAFE_CAST(trip_propagation_pattern AS STRING) AS trip_propagation_pattern,
  SAFE_CAST(has_booking AS INT64) AS has_booking,
  SAFE_CAST(has_booking_cancel AS INT64) AS has_booking_cancel,
  SAFE_CAST(booking_status AS STRING) AS booking_status,
  SAFE_CAST(first_payment_days AS FLOAT64) AS first_payment_days,
  SAFE_CAST(first_payment_trip_distance AS FLOAT64) AS first_payment_trip_distance,
  SAFE_CAST(first_payment_trip_count AS FLOAT64) AS first_payment_trip_count,
  SAFE_CAST(first_payment_user_count AS FLOAT64) AS first_payment_user_count,
  SAFE_CAST(first_payment_vehicle_count AS FLOAT64) AS first_payment_vehicle_count,
  SAFE_CAST(first_payment_auto_enabled AS BOOL) AS first_payment_auto_enabled,
  SAFE_CAST(first_payment_has_auto_distance AS INT64) AS first_payment_has_auto_distance,
  SAFE_CAST(first_payment_daily_trip AS FLOAT64) AS first_payment_daily_trip,
  SAFE_CAST(first_payment_team_size AS FLOAT64) AS first_payment_team_size,
  SAFE_CAST(first_payment_has_trip_exp AS INT64) AS first_payment_has_trip_exp,
  SAFE_CAST(trip_activity_score AS INT64) AS trip_activity_score,
  SAFE_CAST(days_to_first_admin_trip AS FLOAT64) AS days_to_first_admin_trip,
  SAFE_CAST(days_to_first_member_trip AS FLOAT64) AS days_to_first_member_trip,
  SAFE_CAST(pc_login_per_day AS FLOAT64) AS pc_login_per_day,
  SAFE_CAST(contract_period_days AS INT64) AS contract_period_days,
  SAFE_CAST(payment_per_year AS FLOAT64) AS payment_per_year,
  SAFE_CAST(expected_payments AS FLOAT64) AS expected_payments,
  SAFE_CAST(payment_fulfillment_rate AS FLOAT64) AS payment_fulfillment_rate
FROM `carbiz-6f7fc.signup_2025.raw_signup_detail_2025_v1`;