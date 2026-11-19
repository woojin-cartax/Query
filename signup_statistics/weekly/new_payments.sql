WITH s AS (
  SELECT snapshot_date d, company_code c, company_name n, signup_date sd, plan_detail pl, pricing_plan pp,
         contract_type ct, contract_period cp, license_count lc, vehicle_count vc, is_test_account t,
         LAG(plan_detail) OVER (PARTITION BY company_code ORDER BY snapshot_date) prev_pl,
         LAG(snapshot_date) OVER (PARTITION BY company_code ORDER BY snapshot_date) prev_d
  FROM `carbiz-6f7fc.signup_statistics.view_signup_statistics`
  WHERE snapshot_date BETWEEN '2026-11-11' AND '2026-11-18'
)
SELECT c, n, FORMAT_DATETIME('%Y-%m-%d %H:%M:%S', sd) signup, d pay_snap, prev_d, IFNULL(prev_pl,'(없음)') prev_pl, pl, pp, ct, cp, lc, vc,
       DATE_DIFF(d, DATE(sd), DAY) days, t
FROM s
WHERE d BETWEEN '2026-11-12' AND '2026-11-18' AND pl IN ('plus','premium') AND IFNULL(prev_pl,'') NOT IN ('plus','premium')
ORDER BY d, c
