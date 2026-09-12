/* ============================================================================
   10. view_company_stage — 기업별 도입 단계
   ----------------------------------------------------------------------------
   우리 제품의 행동은 두 단계로 일어난다. 이 뷰가 그 구조를 그대로 담는다.

     1단계  고객사와 최고관리자    가입 → 콘솔 진입 → 관리자가 직접 운행
     2단계  관리자 → 사용자 확산   직원 초대 → 직원 진입 → 직원이 운행

   B2C 제품이면 사용자 1명이 단위이고 그 사람의 리텐션을 재면 된다.
   우리는 아니다. 사용자가 아무리 많아도 계약 주체는 기업이고, 확산을 일으키는
   주체는 최고관리자다. 그래서 모든 집계의 단위가 기업이다.

   ★ 2단계로 못 넘어간 기업이 이 뷰의 핵심이다.
     관리자 혼자 쓰다 끝나는 기업과 직원까지 퍼진 기업은 갱신 확률이 다를 것이다.
     「어느 단계에서 멈췄나」와 「거기서 얼마나 오래 멈춰 있나」가 개입 시점을 준다.

   ※ 아하 모먼트 후보가 바뀐다.
     설계안은 「첫 5건 운행」을 후보로 봤는데 그건 사용자 한 명의 행동이다.
     이 구조가 맞다면 진짜 전환점은 stage 3→5, 즉 관리자가 아닌 첫 직원이
     실제로 운행을 기록한 순간이다. days_to_first_member_trip 이 그 측정값이다.
     확정된 것은 아니고, 갱신·이탈과 교차해서 확인해야 한다.

   ※ 성능 — 이 뷰는 raw_trip 전 기간을 훑는다.
     대시보드에서 매번 호출하면 비싸다. 실제로 쓰기 시작하면 뷰가 아니라
     테이블로 굳힌다 (설계안 03번의 「캐시」 층).
   ========================================================================= */

CREATE OR REPLACE VIEW `carbiz-6f7fc.cartax_statistics.view_company_stage` AS
WITH
/* 관리자가 아닌 사용자. 2단계 판정의 기준이 된다.
   created_at 을 여기서 같이 들고 나온다 — 아래에서 raw_user 를 다시 조인하면
   company_seq 가 양쪽에 생겨 모호해진다. */
member_uid AS (
  SELECT user_uid, company_seq, created_at
  FROM `carbiz-6f7fc.cartax_statistics.raw_user`
  WHERE user_uid IS NOT NULL
    AND company_seq IS NOT NULL
    AND NOT `carbiz-6f7fc.cartax_statistics`.is_super_admin(role_seq)
),

/* 운행 — 관리자가 만든 것과 직원이 만든 것을 나눈다 */
trip AS (
  SELECT
    company_seq,
    MIN(IF(is_admin_created, trip_date, NULL))        AS admin_first_trip_date,
    MIN(IF(NOT is_admin_created, trip_date, NULL))    AS member_first_trip_date,
    MAX(trip_date)                                    AS last_trip_date,
    COUNTIF(is_admin_created)                         AS admin_trip_count,
    COUNTIF(NOT is_admin_created)                     AS member_trip_count,
    COUNT(DISTINCT IF(NOT is_admin_created, user_uid, NULL)) AS member_with_trip_count
  FROM `carbiz-6f7fc.cartax_statistics.view_trip`
  WHERE trip_date >= '2016-01-01'
    AND is_countable
  GROUP BY company_seq
),

/* 직원이 앱에 실제로 들어온 시점 */
member_login AS (
  SELECT
    m.company_seq,
    MIN(a.created_at)                                 AS member_first_login_at,
    COUNT(DISTINCT a.user_uid)                        AS member_logged_in_count
  FROM `carbiz-6f7fc.cartax_statistics.raw_login_app` a
  JOIN member_uid m USING (user_uid)
  WHERE a.created_at >= '2016-01-01'
  GROUP BY m.company_seq
),

/* 관리자가 아닌 사용자가 처음 만들어진 시점 = 초대 시점 */
member_created AS (
  SELECT company_seq, MIN(created_at) AS member_first_created_at
  FROM member_uid
  GROUP BY company_seq
),

/* 첫 결제 성공 */
pay AS (
  SELECT company_seq, MIN(event_date) AS first_payment_date
  FROM `carbiz-6f7fc.cartax_statistics.view_payment`
  WHERE result = 'success' AND source = 'payment'
  GROUP BY company_seq
),

base AS (
  SELECT
    c.company_seq,
    c.company_code,
    c.company_name,
    c.plan_name,
    c.is_withdrawn,
    c.is_test_account,
    c.signup_date_d                                   AS signup_date,
    c.contract_end_date,
    c.is_auto_pay,
    c.license_count,

    /* ── 1단계 이정표 ── */
    DATE(l.admin_first_login_at)                      AS admin_first_login_date,
    t.admin_first_trip_date,

    /* ── 2단계 이정표 ── */
    DATE(mc.member_first_created_at)                  AS member_first_created_date,
    DATE(ml.member_first_login_at)                    AS member_first_login_date,
    t.member_first_trip_date,

    /* ── 규모 ── */
    IFNULL(u.user_count_admin, 0)                     AS admin_count,
    IFNULL(u.user_count_member_active, 0)             AS member_active_count,
    IFNULL(ml.member_logged_in_count, 0)              AS member_logged_in_count,
    IFNULL(t.member_with_trip_count, 0)               AS member_with_trip_count,
    IFNULL(t.admin_trip_count, 0)                     AS admin_trip_count,
    IFNULL(t.member_trip_count, 0)                    AS member_trip_count,
    t.last_trip_date,
    p.first_payment_date,

    /* 수집이 구조적으로 제한된 기업. 운행이 적은 것을 사용 부진으로 오진하지 않기 위해 */
    c.has_restricted_logging
  FROM `carbiz-6f7fc.cartax_statistics.view_company` c
  LEFT JOIN `carbiz-6f7fc.cartax_statistics.view_login_company` l USING (company_seq)
  LEFT JOIN `carbiz-6f7fc.cartax_statistics.view_user_company`  u USING (company_seq)
  LEFT JOIN trip           t  USING (company_seq)
  LEFT JOIN member_login   ml USING (company_seq)
  LEFT JOIN member_created mc USING (company_seq)
  LEFT JOIN pay            p  USING (company_seq)
)

SELECT
  b.*,

  /* ── 도달 단계 ──────────────────────────────────────────────────────
     가장 멀리 간 이정표. 뒤 단계에 도달했으면 앞 단계는 지났다고 본다
     (기록이 없어도 — 초기 데이터에 구멍이 있을 수 있다).                   */
  CASE
    WHEN b.member_first_trip_date    IS NOT NULL THEN 5
    WHEN b.member_first_login_date   IS NOT NULL THEN 4
    WHEN b.member_first_created_date IS NOT NULL THEN 3
    WHEN b.admin_first_trip_date     IS NOT NULL THEN 2
    WHEN b.admin_first_login_date    IS NOT NULL THEN 1
    ELSE 0
  END                                               AS stage,

  CASE
    WHEN b.member_first_trip_date    IS NOT NULL THEN '5 직원 운행'
    WHEN b.member_first_login_date   IS NOT NULL THEN '4 직원 진입'
    WHEN b.member_first_created_date IS NOT NULL THEN '3 직원 초대'
    WHEN b.admin_first_trip_date     IS NOT NULL THEN '2 관리자 운행'
    WHEN b.admin_first_login_date    IS NOT NULL THEN '1 관리자 진입'
    ELSE '0 가입만'
  END                                               AS stage_label,

  /* 1단계(고객사·최고관리자)인가 2단계(확산)인가 */
  IF(b.member_first_created_date IS NOT NULL, 'expansion', 'admin')
                                                    AS stage_group,

  /* ── 단계별 소요일 ─────────────────────────────────────────────────
     아하 모먼트 탐색의 재료다. 빨리 도달한 기업과 못 한 기업을 갈라
     갱신·이탈과 교차한다.                                                  */
  DATE_DIFF(b.admin_first_login_date,    b.signup_date, DAY) AS days_to_admin_login,
  DATE_DIFF(b.admin_first_trip_date,     b.signup_date, DAY) AS days_to_admin_trip,
  DATE_DIFF(b.member_first_created_date, b.signup_date, DAY) AS days_to_member_invite,
  DATE_DIFF(b.member_first_login_date,   b.signup_date, DAY) AS days_to_member_login,
  DATE_DIFF(b.member_first_trip_date,    b.signup_date, DAY) AS days_to_member_trip,
  DATE_DIFF(b.first_payment_date,        b.signup_date, DAY) AS days_to_first_payment,

  /* 관리자가 첫 직원을 확산시키는 데 걸린 시간.
     설계안의 「첫 5건 운행」보다 이쪽이 진짜 전환점일 수 있다 */
  DATE_DIFF(b.member_first_trip_date, b.admin_first_trip_date, DAY)
                                                    AS days_admin_to_member_trip,

  /* ── 막힘 ──────────────────────────────────────────────────────────
     마지막 이정표 이후 흐른 날. 길수록 그 단계에 갇혀 있다는 뜻이다.       */
  DATE_DIFF(
    CURRENT_DATE("Asia/Seoul"),
    GREATEST(
      IFNULL(b.member_first_trip_date,    DATE '1970-01-01'),
      IFNULL(b.member_first_login_date,   DATE '1970-01-01'),
      IFNULL(b.member_first_created_date, DATE '1970-01-01'),
      IFNULL(b.admin_first_trip_date,     DATE '1970-01-01'),
      IFNULL(b.admin_first_login_date,    DATE '1970-01-01'),
      IFNULL(b.signup_date,               DATE '1970-01-01')),
    DAY)                                            AS days_since_last_milestone,

  /* ── 판정 ──────────────────────────────────────────────────────────
     확산이 일어났나. 초대만 하고 끝난 것은 확산이 아니다 —
     직원이 실제로 운행을 기록해야 제품이 쓰이고 있는 것이다.               */
  (b.member_trip_count > 0)                         AS has_expanded,

  /* 초대는 했는데 아무도 운행하지 않았다. 온보딩이 막힌 지점이다 */
  (b.member_first_created_date IS NOT NULL AND b.member_trip_count = 0)
                                                    AS invited_but_no_trip,

  /* 관리자 혼자 쓰고 있다. 2단계로 한 번도 못 갔다 */
  (b.admin_trip_count > 0 AND b.member_first_created_date IS NULL)
                                                    AS admin_only,

  /* 직원 중 실제로 운행한 비율. 확산의 깊이 */
  SAFE_DIVIDE(b.member_with_trip_count, NULLIF(b.member_active_count, 0))
                                                    AS member_activation_rate,

  /* 유료 전환 전에 확산이 일어났나.
     확산이 결제를 부르는지, 결제가 확산을 부르는지 보려면 순서를 알아야 한다 */
  CASE
    WHEN b.first_payment_date IS NULL              THEN NULL
    WHEN b.member_first_trip_date IS NULL          THEN FALSE
    ELSE b.member_first_trip_date < b.first_payment_date
  END                                               AS expanded_before_payment

FROM base b;
