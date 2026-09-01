CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_90days.view_signup_90days_monthly_by_plan` AS
/* =========================
   월별 요금제 분포 — 리포트 두 번째 표.

     요금제별 | 기업수 | 라이선스 수 | 평균라이선스

   plan_detail 4값(premium / plus / free / trial)이 상호배타이므로
   기업수의 합이 08_monthly_summary의 signup_count와 정확히 일치한다.
   라이선스 합도 08의 license_total과 일치한다.

   집계 기준과 필터는 08과 동일하다. 같은 토대(06_monthly_base)를 읽는다.
========================= */

SELECT
  ref_month,
  plan_detail,

  COUNT(*) AS company_count,
  SUM(license_count_adjusted) AS license_total,
  SAFE_DIVIDE(SUM(license_count_adjusted), COUNT(*)) AS avg_license,

  /* 참고용 */
  SUM(vehicle_count) AS vehicle_count,
  SUM(user_count) AS user_count

FROM `carbiz-6f7fc.signup_90days.view_signup_90days_monthly_base`
WHERE is_counted
  AND signup_year_month = ref_month
GROUP BY ref_month, plan_detail
ORDER BY ref_month DESC,
         /* 리포트 표 순서: 프리미엄 → 플러스 → 무료 → 체험중 */
         CASE plan_detail WHEN 'premium' THEN 1 WHEN 'plus' THEN 2
                          WHEN 'free' THEN 3 ELSE 4 END;
