CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_90days.view_signup_90days_monthly_summary` AS

WITH filtered AS (
  /* 집계 대상 필터: 중복기업/테스트계정/탈퇴기업 제외 */
  SELECT
    *,
    /* 무료/체험은 라이선스 수 개념이 없으므로 차량수로 대체 */
    IF(plan_status IN ('free', 'trial'), vehicle_count, license_type) AS effective_license_count
  FROM `carbiz-6f7fc.signup_90days.view_signup_90days_latest`
  WHERE is_test_account = FALSE
    AND is_withdrawn_company = FALSE
    AND duplicate_exclude_flag = FALSE
)

SELECT
  signup_year_month,

  /* 1) 회사수 / 차량수 / 라이선스 수 */
  COUNT(*) AS company_count,
  SUM(vehicle_count) AS vehicle_count,
  SUM(effective_license_count) AS license_count,

  /* 2) 전환율 / 평균 라이선스수 */
  SAFE_DIVIDE(SUM(is_paid_flag), COUNT(*)) AS paid_conversion_rate,
  SAFE_DIVIDE(SUM(effective_license_count), COUNT(*)) AS avg_license_count,
  SAFE_DIVIDE(SUM(IF(is_paid_flag = 1, effective_license_count, 0)), NULLIF(SUM(is_paid_flag), 0)) AS avg_license_count_paid,

  /* 3) 요금제별 분포(체험/무료/유료) - 건수 */
  COUNTIF(plan_status = 'trial') AS trial_count,
  COUNTIF(plan_status = 'free') AS free_count,
  COUNTIF(plan_status = 'paid') AS paid_count,

  /* 요금제별 분포 - 비율 */
  SAFE_DIVIDE(COUNTIF(plan_status = 'trial'), COUNT(*)) AS trial_ratio,
  SAFE_DIVIDE(COUNTIF(plan_status = 'free'), COUNT(*)) AS free_ratio,
  SAFE_DIVIDE(COUNTIF(plan_status = 'paid'), COUNT(*)) AS paid_ratio

FROM filtered
GROUP BY signup_year_month
ORDER BY signup_year_month;
