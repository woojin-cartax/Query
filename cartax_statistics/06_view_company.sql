/* ============================================================================
   05. view_company — 기업 마스터 + 현재 결제 상태
   ----------------------------------------------------------------------------
   기업당 1행. 대시보드와 중복 판정이 전부 여기서 출발한다.

   ★ company_number (사업자등록번호)
     이게 오면 중복 판정이 근본적으로 달라진다. 지금은 회사명 문자열로 추측하고
     합친 것이 맞는지 검증할 방법이 없다.
     다만 특정 시점 이후 가입 건에만 있다. 그래서 회사명 정규화를 없애지 않고
     둘을 같이 둔다 — 사업자번호가 있으면 그걸 쓰고, 없으면 이름으로 떨어진다.

   ※ 회사명 정규화와 테스트 계정 판정은 signup_90days/04_view_derived.sql 과
     글자 그대로 같은 규칙이다. 두 시스템의 숫자가 갈리면 안 된다.
     한쪽을 고치면 반드시 다른 쪽도 고친다.
   ========================================================================= */

CREATE OR REPLACE VIEW `carbiz-6f7fc.cartax_statistics.view_company` AS
SELECT
  c.company_seq,
  c.company_code,
  c.company_name,
  c.company_number,
  c.business_type,
  c.plan_level,
  `carbiz-6f7fc.cartax_statistics`.plan_name(c.plan_level) AS plan_name,
  c.enabled_state,
  c.is_withdrawn,
  c.signup_date,
  DATE(c.signup_date)                             AS signup_date_d,
  c.last_login_at,
  c.join_path,
  c.join_device,
  c.coalition_company,
  c.ga_client_id,
  c.email_domain,
  c.address_region,
  c.invite_sms_count,

  /* ── 중복 판정 ──────────────────────────────────────────────────────
     1순위는 사업자등록번호다. 숫자만 남긴다 — 하이픈 표기가 섞여 온다.
     빈 문자열은 NULL 로 만든다. 없는 값끼리 서로 같다고 묶이면 안 된다.        */
  NULLIF(REGEXP_REPLACE(IFNULL(c.company_number, ''), r'[^0-9]', ''), '')
                                                  AS company_number_norm,

  /* 2순위는 정규화 회사명. 사업자번호가 없는 기업을 위한 대비다.
     표기 흔들림만 제거한다 — 법인격 표기와 공백. 의미를 바꾸는 절단은 안 한다.
     NORMALIZE(NFKC)를 먼저 거는 것이 중요하다. 전각 괄호가 실제로 섞여 있다. */
  REGEXP_REPLACE(
    REGEXP_REPLACE(
      LOWER(TRIM(NORMALIZE(c.company_name, NFKC))),
      r'\(주\)|\(유\)|\(재\)|\(사\)|주식회사|유한회사|유한책임회사|재단법인|사단법인|농업회사법인|영어조합법인',
      ''),
    r'\s+', ''
  )                                               AS company_name_norm,

  /* 테스트 계정. COALESCE 가 아니라 IFNULL 로 감싸는 이유는 없다 —
     여기는 수동 판정 테이블을 조인하지 않아 3값 논리 문제가 생기지 않는다.
     수동 판정이 필요해지면 signup_90days 의 manual_override 처럼 붙이되
     그때 COALESCE 를 반드시 넣는다. (FALSE OR NULL = NULL) */
  REGEXP_CONTAINS(
    CONCAT(
      REGEXP_REPLACE(LOWER(NORMALIZE(IFNULL(c.company_name, ''), NFKC)), r'\s+', ''),
      ' ',
      LOWER(IFNULL(c.company_code, ''))
    ),
    r'(영티포|카택스|테스트|4424|유진의|조훈|낙현회사|퍼피또리)'
  )                                               AS is_test_account,

  /* ── 현재 결제 상태 ────────────────────────────────────────────────
     결제 이력으로 대신할 수 없다. 무료·체험 기업 81%는 결제 이력이 없다.     */
  s.is_auto_pay,
  s.pay_method,
  s.previous_pay_method,
  s.pay_cycle,
  s.contract_begin_date,
  s.contract_end_date,
  s.license_count,
  s.is_trial_active,
  s.trial_begin_date,
  s.trial_end_date,
  s.trial_cancel_date,
  s.is_downgrade_exempt,

  /* 계약 만료까지 남은 일수. 음수면 이미 지났다.
     is_auto_pay 가 FALSE 이고 이 값이 임박하면 이탈 위험 신호다 —
     자동결제를 꺼 둔 채 만료를 기다리는 상태다. */
  DATE_DIFF(s.contract_end_date, CURRENT_DATE("Asia/Seoul"), DAY)
                                                  AS days_to_contract_end,

  /* 무료체험 중 구독을 취소했나. 아직 고객인 상태에서 보내는 신호다.
     탈퇴 사유는 사후 분석이지만 이건 개입할 수 있는 시점이다. */
  (s.trial_cancel_date IS NOT NULL)               AS has_cancelled_trial,

  /* ── 설정 ─────────────────────────────────────────────────────────
     둘만 받는다. 둘 다 「수집하는 데이터의 양 자체」를 정하는 설정이라,
     운행 데이터가 왜 비어 있는지를 설명한다.
       setting_save_map_point  X미저장이면 경로가 아예 안 남는다
       setting_privacy_mode    none 이 아니면 운행이 가려진다
     이걸 모르고 「운행이 적다」고 읽으면 사용 부진으로 오진한다. */
  c.setting_save_map_point,
  c.setting_privacy_mode,

  /* 운행 기록이 구조적으로 제한돼 있나. 사용 부진과 구분해야 한다 */
  (c.setting_save_map_point = 'X' OR c.setting_privacy_mode != 'none')
                                                  AS has_restricted_logging,

  c.updated_at
FROM `carbiz-6f7fc.cartax_statistics.raw_company` c
LEFT JOIN `carbiz-6f7fc.cartax_statistics.raw_company_pay_state` s
  ON c.company_seq = s.company_seq;
