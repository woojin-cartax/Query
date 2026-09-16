/* ============================================================================
   94. 신규 가입 기업 주별 추이 — 조회용. 아무것도 바꾸지 않는다
   ----------------------------------------------------------------------------
   CX 주간 리포트용. 주 경계는 목요일 시작 ~ 수요일 종료다.
   기간을 바꾸려면 아래 BETWEEN 두 날짜만 고친다.

   스캔 약 12 MB. 반복 실행해도 비용 부담이 없다.

   ※ 수집 공백(2026-06-30~08-03)은 이 집계에 영향이 없다.
     집계 기준이 snapshot_date 가 아니라 signup_date 이고, 기업이 누락되려면
     그 기업의 90일 윈도우 전체가 34일짜리 공백 안에 들어가야 하는데 불가능하다.
     실측으로도 그 구간 주간 수치가 앞뒤와 같은 수준이었다.

   ※ 원본은 2026-01-26 부터 시작한다. 그보다 90일 이전(≈2025-10-28 이전)에
     가입한 기업은 이 테이블에 나타난 적이 없다. 2026년 내 중복은 정상 처리되지만,
     「2025년에 이미 가입했던 기업인가」는 그 구간에 대해 판별할 수 없다.
   ========================================================================= */
WITH first_signup AS (
  SELECT
    IFNULL(NULLIF(company_name_norm, ''), company_code) AS company_key,
    MIN(DATE(signup_date))                             AS signup_d
  FROM `carbiz-6f7fc.signup_90days.view_signup_90days_latest`
  WHERE NOT is_test_account
    AND signup_date IS NOT NULL
  GROUP BY company_key
)
SELECT
  week_start,
  DATE_ADD(week_start, INTERVAL 6 DAY) AS week_end,
  COUNT(*)                             AS new_companies
FROM (
  SELECT DATE_TRUNC(signup_d, WEEK(THURSDAY)) AS week_start
  FROM first_signup
  WHERE signup_d BETWEEN '2026-01-01' AND '2026-09-16'
)
GROUP BY week_start
ORDER BY week_start;
