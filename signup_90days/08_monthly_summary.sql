CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_90days.view_signup_90days_monthly_summary` AS
/* =========================
   월별 요약 — 리포트 첫 번째 표.

     가입수 | 전환율(결제) | 평균라이선스(결제) | 평균라이선스(전체)

   그 달 말일 스냅샷에서, 그 달에 가입한 기업만 센다.
   테스트 계정 / 탈퇴 기업 / 중복 계정은 제외한다 (06_monthly_base의 is_counted).

   라이선스는 항상 license_count_adjusted를 쓴다. 무료·체험 기업은 라이선스가
   100으로 기본 지급되므로 원본 license_count를 그대로 더하면 실제 규모가 왜곡된다.

   09_monthly_by_plan과 같은 토대(06_monthly_base)를 쓰므로 두 표의 합계가 맞물린다.
========================= */

SELECT
  ref_month,

  /* 가입수 */
  COUNT(*) AS signup_count,

  /* 전환율(결제) — 유료 기업 비율 */
  SAFE_DIVIDE(SUM(is_paid_flag), COUNT(*)) AS paid_conversion_rate,

  /* 평균라이선스(결제) — 유료 기업만 */
  SAFE_DIVIDE(
    SUM(IF(is_paid_flag = 1, license_count_adjusted, 0)),
    NULLIF(SUM(is_paid_flag), 0)
  ) AS avg_license_paid,

  /* 평균라이선스(전체) */
  SAFE_DIVIDE(SUM(license_count_adjusted), COUNT(*)) AS avg_license_all,

  /* 참고용 원자료 */
  SUM(is_paid_flag) AS paid_count,
  SUM(license_count_adjusted) AS license_total,
  SUM(vehicle_count) AS vehicle_count

FROM `carbiz-6f7fc.signup_90days.view_signup_90days_monthly_base`
WHERE is_counted
  AND signup_year_month = ref_month     -- 그 달에 가입한 기업만
GROUP BY ref_month
ORDER BY ref_month DESC;
