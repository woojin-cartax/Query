/* ============================================================================
   04. view_signup_statistics — 파생 컬럼. 판정은 전부 여기서 한 번만 한다
   ----------------------------------------------------------------------------
   아래 뷰들은 물려받기만 한다. 같은 판정을 두 곳에서 만들지 않는다.
   (policy/10_naming.md — signup_90days 에서 유료 판정이 두 벌로 갈려
    같은 KPI 뷰 안에서 유료 기업 수가 494 와 496 으로 나온 적이 있다)

   ★ signup_90days/04_view_derived.sql 과 판정 규칙을 맞춘다. 두 피드의 같은
     지표가 다른 숫자를 내면 안 된다. 한쪽을 고치면 반드시 다른 쪽도 고친다.

   ★ 이 피드에만 corporate_number 가 있다. 중복 판정이 근본적으로 달라진다 —
     아래 company_key 참조.
   ========================================================================= */

CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_statistics.view_signup_statistics` AS
SELECT
  r.*,

  /* ── 요금제 ────────────────────────────────────────────────────────
     판정은 이 컬럼 하나에서만 한다. plan_status 와 is_paid_flag 가 여기서 파생된다.
     pricing_plan 값이 대문자(FREE/PLUS/PREMIUM)다 — 소문자로 비교하면 전부 빗나간다.
     실제로 signup_90days 에서 그 오류로 2,502개사가 유료로 잡힌 적이 있다. */
  CASE
    WHEN r.pricing_plan IS NULL OR UPPER(TRIM(r.pricing_plan)) = 'FREE' THEN 'free'
    WHEN COALESCE(r.is_trial_active, FALSE)                             THEN 'trial'
    WHEN UPPER(TRIM(r.pricing_plan)) = 'PLUS'                           THEN 'plus'
    ELSE 'premium'
  END AS plan_detail,

  /* ── 사업자등록번호 정규화 ─────────────────────────────────────────
     숫자만 남긴다 — 하이픈 표기가 섞여 온다.
     빈 문자열은 NULL 로. 없는 값끼리 서로 같다고 묶이면 안 된다. */
  NULLIF(REGEXP_REPLACE(IFNULL(r.corporate_number, ''), r'[^0-9]', ''), '')
                                                  AS corporate_number_norm,

  /* ── 정규화 회사명 ────────────────────────────────────────────────
     표기 흔들림만 제거한다 — 법인격 표기와 공백. 의미를 바꾸는 절단은 안 한다.
     NORMALIZE(NFKC) 를 먼저 거는 것이 중요하다. 전각 괄호가 실제로 섞여 있다
     (（주） 등). 반각만 열거하면 그 회사들이 정규화에서 빠져나간다. */
  REGEXP_REPLACE(
    REGEXP_REPLACE(
      LOWER(TRIM(NORMALIZE(r.company_name, NFKC))),
      r'\(주\)|\(유\)|\(재\)|\(사\)|주식회사|유한회사|유한책임회사|재단법인|사단법인|농업회사법인|영농조합법인|영어조합법인',
      ''),
    r'\s+', ''
  )                                               AS company_name_norm,

  /* ── 회사명이 아닌 값 ─────────────────────────────────────────────
     업태나 형태를 적어 넣은 일반명사다. 회사를 식별하지 못한다.
     이름으로 묶으면 서로 완전히 다른 사업자가 한 덩어리가 된다.

     실측(2026-10-05): 해당 100개사가 11개 이름그룹에 뭉쳐 있고, 그중 85개사가
     서로 다른 사업자였다. 「개인택시」 하나에 사업자 25곳이 들어 있다.
     이름 판정만 쓰면 그 그룹에서 24개사가 부당하게 중복 제외된다. */
  REGEXP_CONTAINS(
    REGEXP_REPLACE(REGEXP_REPLACE(
      LOWER(TRIM(NORMALIZE(IFNULL(r.company_name, ''), NFKC))),
      r'\(주\)|\(유\)|주식회사|유한회사', ''), r'\s+', ''),
    r'^(개인택시|개인화물|개별화물|개인|null|none|무|없음|미정|1|-|\.)$'
  )                                               AS is_generic_name,

  /* ── 테스트 계정 ──────────────────────────────────────────────────
     회사명과 회사코드를 이어붙여 키워드로 판정한다.
     회사명은 company_name_norm 과 같은 방식으로 정규화한다 — 전각·공백 변형으로
     키워드를 빠져나가는 것을 막는다. */
  REGEXP_CONTAINS(
    CONCAT(
      REGEXP_REPLACE(LOWER(NORMALIZE(IFNULL(r.company_name, ''), NFKC)), r'\s+', ''),
      ' ', LOWER(IFNULL(r.company_code, ''))
    ),
    r'(영티포|카택스|테스트|4424|유진의|조훈|낙현회사|퍼피또리)'
  )                                               AS is_test_account,

  /* ── 가입 시점 파생 ───────────────────────────────────────────────── */
  DATE(r.signup_date)                                        AS signup_date_d,
  FORMAT_DATE('%Y-%m', DATE(r.signup_date))                  AS signup_year_month,
  DATE_DIFF(r.snapshot_date, DATE(r.signup_date), DAY)       AS days_since_signup,
  CASE WHEN r.first_trip_date_start IS NULL OR r.signup_date IS NULL THEN NULL
       ELSE DATE_DIFF(DATE(r.first_trip_date_start), DATE(r.signup_date), DAY)
  END                                                        AS days_to_first_trip,

  /* ── 라이선스 보정 ────────────────────────────────────────────────
     무료·체험 기업은 라이선스가 100으로 기본 지급된다. 원값을 그대로 더하면
     실제 규모가 왜곡되므로 유료만 원값을 쓰고 나머지는 차량 수로 대체한다. */
  IF(CASE
       WHEN r.pricing_plan IS NULL OR UPPER(TRIM(r.pricing_plan)) = 'FREE' THEN 'free'
       WHEN COALESCE(r.is_trial_active, FALSE)                             THEN 'trial'
       WHEN UPPER(TRIM(r.pricing_plan)) = 'PLUS'                           THEN 'plus'
       ELSE 'premium'
     END IN ('plus','premium'), r.license_count, r.vehicle_count)
                                                  AS license_count_adjusted
FROM `carbiz-6f7fc.signup_statistics.raw_signup_statistics` r;
