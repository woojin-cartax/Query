/* ============================================================================
   91. 신규 가입 회사 추이 — 조회용. 아무것도 바꾸지 않는다
   ----------------------------------------------------------------------------
   주간(목~수) · 월간 신규 회사 수. 정의는 README 「주간 가입 리포트 정의」.

   신규 회사 = 그 회사의 첫 계정, 또는 그보다 먼저 만든 같은 회사 계정이
               전부 「6개월 넘게 활동 없음 + 지금 유료 아님」인 새 계정.

   ★ 중복은 가입 시점 기준으로 판정한다. 각 계정은 자기보다 먼저 만든 같은 회사
     계정하고만 비교한다. 나중 계정 때문에 예전 가입이 중복이 되지 않는다.

   한계 (README 에 상세)
   - 기존 계정의 마지막 활동·유료 여부는 snap 시점 값이다. 가입 당시 값이 아니다.
     가입 뒤에 활동한 기존 계정도 「활동 중」으로 본다(보수적으로 재가입 쪽).
   - snap 스냅샷에 남은 계정만 본다. 삭제된 계정은 안 보인다 — 오래된 연도일수록
     가입 수가 실제보다 적고, 삭제된 옛 계정의 회사가 돌아오면 신규로 잡힌다.
   - 가입유형(PC/모바일)은 이 피드에 없다.

   snap 하나만 고쳐 쓴다. 스캔 약 4 MB.
   ========================================================================= */
DECLARE snap DATE DEFAULT '2026-10-15';

CREATE TEMP TABLE judged AS
WITH a AS (
  SELECT
    company_code,
    /* 같은 아이디인데 사업자번호가 다른 계정 — 같은 회사로 수동 지정 */
    CASE WHEN company_code IN ('U349', 'U350') THEN 'M:urban01'
         ELSE company_key END                                   AS company_key,
    signup_date,
    GREATEST(IFNULL(last_trip_date_start, DATETIME '1900-01-01'),
             IFNULL(pc_last_login_date,   DATETIME '1900-01-01'),
             signup_date)                                       AS last_act,
    (UPPER(pricing_plan) <> 'FREE' AND NOT is_trial_active)     AS paid
  FROM `carbiz-6f7fc.signup_statistics.view_signup_statistics_dedup`
  WHERE snapshot_date = snap
    AND NOT is_test_account
    AND company_code NOT IN ('X176', 'H1424')   -- 판정에 안 걸린 테스트 계정
    AND signup_date IS NOT NULL
),
blockers AS (
  /* 먼저 만든 같은 회사 계정 중 「활동 중이거나 유료」인 것의 수 */
  SELECT cur.company_code,
         COUNTIF(p.paid OR DATETIME_DIFF(cur.signup_date, p.last_act, DAY) < 182) AS n
  FROM a AS cur
  JOIN a AS p
    ON p.company_key = cur.company_key          -- NULL 키(일반명사 회사명)는 묶이지 않는다
   AND p.signup_date < cur.signup_date
  GROUP BY cur.company_code
)
SELECT a.company_code, DATE(a.signup_date) AS signup_d,
       IFNULL(b.n, 0) = 0 AS is_new
FROM a LEFT JOIN blockers b USING (company_code);

-- 월별 (연도 비교용)
SELECT EXTRACT(YEAR FROM signup_d) AS yr, EXTRACT(MONTH FROM signup_d) AS mon,
       COUNT(*) AS accounts, COUNTIF(is_new) AS new_companies
FROM judged
GROUP BY yr, mon
ORDER BY yr, mon;

-- 주별 (목~수, 2026년)
SELECT DATE_TRUNC(signup_d, WEEK(THURSDAY)) AS week_start,
       COUNT(*) AS accounts, COUNTIF(is_new) AS new_companies
FROM judged
WHERE signup_d >= '2026-01-01'
GROUP BY week_start
ORDER BY week_start;
