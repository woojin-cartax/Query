/* ============================================================================
   05. view_signup_statistics_dedup — 중복기업 판정
   ----------------------------------------------------------------------------
   signup_90days 와 결정적으로 다른 점이 하나 있다. 여기에는
   corporate_number 가 있어서 **추측 대신 확정**할 수 있다.

   ★ 판정 키의 순서

     1순위  사업자등록번호        — 같으면 같은 법인이다. 확정
     2순위  정규화 회사명         — 사업자번호가 없을 때만. 추측
     판정 안 함  일반명사          — 「개인택시」류. 회사를 식별하지 못한다

   실측 (2026-10-05, 테스트 제외 20,417개사):

     사업자번호 보유        14,907  (73.0%)
     사업자번호 기준 중복    2,764
     이름 기준 중복          4,573
     **이름은 같은데 사업자번호가 다르다   464**   ← 잘못 묶이고 있었다
     **사업자번호는 같은데 이름이 다르다   344**   ← 이름 판정이 놓치고 있었다

   앞의 464 가 더 아프다. 묶인 쪽은 중복 제외로 통계에서 사라지는데,
   **잘못 묶인 것은 눈에 보이지 않는다.** 덜 묶인 것은 나중에 발견된다.

   이름 판정만 쓰면 **369개사가 부당하게 제외된다** (일반명사 79 + 동명이인 290).
   「개인택시」 한 그룹에 서로 다른 사업자가 25곳 들어 있다.

   ※ 중복 "그룹"을 만들 뿐이고, 그룹 안에서 누구를 남길지는 06 에서 정한다.
   ========================================================================= */

CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_statistics.view_signup_statistics_dedup` AS
WITH keyed AS (
  SELECT
    v.*,

    /* ── 중복 판정 키 ──────────────────────────────────────────────────
       사업자번호가 있으면 그것, 없으면 정규화 회사명.
       일반명사이고 사업자번호도 없으면 NULL — 묶지 않는다.

       접두사를 붙이는 이유: 사업자번호 '1234567890' 과 회사명 '1234567890' 이
       우연히 같을 때 서로 묶이는 것을 막는다. */
    CASE
      WHEN v.corporate_number_norm IS NOT NULL
        THEN CONCAT('C:', v.corporate_number_norm)
      WHEN v.is_generic_name OR v.company_name_norm IS NULL OR v.company_name_norm = ''
        THEN NULL
      ELSE CONCAT('N:', v.company_name_norm)
    END                                           AS company_key,

    IF(v.corporate_number_norm IS NOT NULL, 'corp_no',
       IF(v.is_generic_name, 'none', 'name'))     AS company_key_source
  FROM `carbiz-6f7fc.signup_statistics.view_signup_statistics` v
  WHERE NOT v.is_test_account
),
grouped AS (
  SELECT
    k.*,
    /* 같은 키를 쓰는 계정 수. NULL 키는 묶지 않으므로 1로 둔다 */
    IF(k.company_key IS NULL, 1,
       COUNT(*) OVER (PARTITION BY k.snapshot_date, k.company_key))
                                                  AS account_count,
    IF(k.company_key IS NULL, 0,
       SUM(IF(k.plan_detail IN ('plus','premium'), 1, 0))
         OVER (PARTITION BY k.snapshot_date, k.company_key))
                                                  AS paid_account_count,

    /* 유지 우선순위. 마지막 company_code 가 결정적 tiebreak 다 —
       앞의 네 키가 모두 동점인 빈 계정이 실제로 있고, tiebreak 없이는
       실행마다 다른 계정이 남는다. signup_90days 에서 세 번 실행에 세 번
       다른 결과를 확인했다 (J1247 → Q229 → A1007). */
    ROW_NUMBER() OVER (
      PARTITION BY k.snapshot_date, k.company_key
      ORDER BY k.vehicle_count DESC, k.trip_count_total DESC,
               k.total_distance DESC, k.user_count DESC, k.company_code
    )                                             AS keep_rank
  FROM keyed k
)
SELECT
  g.*,

  /* 같은 법인·같은 이름으로 여러 계정이 있나 */
  (g.company_key IS NOT NULL AND g.account_count > 1) AS is_duplicate_company,

  /* 실사용 중인 무료·체험 계정. 최근 2주 운행 14회 이상 = 하루 최소 1회.
     유료 계정과 같은 키로 묶였더라도 실제로 쓰고 있으면 별개로 인정한다.
     signup_90days 와 같은 기준이다. */
  IF(g.plan_detail NOT IN ('plus','premium') AND g.trip_count_recent_2w >= 14, 1, 0)
                                                  AS is_active_free,

  /* ── 최종 제외 판정 ───────────────────────────────────────────────
       키가 없다            -> 제외하지 않는다. 묶을 근거가 없다
       유료 2개 이상        -> 전부 유지. 계열사·지사가 각자 결제하는 경우가 있다
       유료 정확히 1개      -> 유료 + 실사용 무료·체험 유지
       유료 0개             -> 활동량 1위만 유지                               */
  CASE
    WHEN g.company_key IS NULL      THEN FALSE
    WHEN g.account_count = 1        THEN FALSE
    WHEN g.paid_account_count >= 2  THEN FALSE
    WHEN g.paid_account_count = 1
      THEN NOT (g.plan_detail IN ('plus','premium')
                OR (g.trip_count_recent_2w >= 14))
    ELSE g.keep_rank > 1
  END                                             AS duplicate_exclude_flag
FROM grouped g;
