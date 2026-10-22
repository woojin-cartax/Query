/* ============================================================================
   91. 신규 가입 회사 추이 — 조회용. 아무것도 바꾸지 않는다
   ----------------------------------------------------------------------------
   주간(목~수) · 월간 신규 회사 수. 정의는 README 「주간 가입 리포트 정의」.

   신규 회사 = 그 회사의 첫 계정. 그보다 먼저 만든 같은 회사 계정이 하나라도
               있으면 신규가 아니다(공백 기간 무관 — 6개월 휴면 예외는 2026-10-23 폐지).
   신규가 아닌 것 = 재가입(이전 계정에 이 가입 전 운행 기록 있음) / 중복(없음).

   ★ 중복은 가입 시점 기준으로 판정한다. 각 계정은 자기보다 먼저 만든 같은 회사
     계정하고만 비교한다. 나중 계정 때문에 예전 가입이 중복이 되지 않는다.

   한계 (README 에 상세)
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
    first_trip_date_start
  FROM `carbiz-6f7fc.signup_statistics.view_signup_statistics_dedup`
  WHERE snapshot_date = snap
    AND NOT is_test_account
    AND company_code NOT IN ('X176', 'H1424', 'T1436')   -- 판정에 안 걸린 테스트 계정
    AND signup_date IS NOT NULL
),
blockers AS (
  /* 먼저 만든 같은 회사 계정의 수, 그중 이 가입 전에 운행한 계정이 있나 */
  SELECT cur.company_code, COUNT(*) AS n,
         LOGICAL_OR(p.first_trip_date_start < cur.signup_date) AS prior_drove
  FROM a AS cur
  JOIN a AS p
    ON p.company_key = cur.company_key          -- NULL 키(일반명사 회사명)는 묶이지 않는다
   AND p.signup_date < cur.signup_date
  GROUP BY cur.company_code
)
SELECT a.company_code, DATE(a.signup_date) AS signup_d,
       CASE WHEN b.n IS NULL           THEN '신규'
            WHEN IFNULL(b.prior_drove, FALSE) THEN '재가입'
            ELSE '중복' END AS kind,
       b.n IS NULL AS is_new
FROM a LEFT JOIN blockers b USING (company_code);

-- 월별 (연도 비교용)
SELECT EXTRACT(YEAR FROM signup_d) AS yr, EXTRACT(MONTH FROM signup_d) AS mon,
       COUNT(*) AS accounts, COUNTIF(is_new) AS new_companies
FROM judged
GROUP BY yr, mon
ORDER BY yr, mon;

-- 주별 (목~수, 2026년)
SELECT DATE_TRUNC(signup_d, WEEK(THURSDAY)) AS week_start,
       COUNT(*) AS accounts, COUNTIF(is_new) AS new_companies,
       COUNTIF(kind = '재가입') AS resignups, COUNTIF(kind = '중복') AS duplicates
FROM judged
WHERE signup_d >= '2026-01-01'
GROUP BY week_start
ORDER BY week_start;
