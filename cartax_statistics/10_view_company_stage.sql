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

   ※ 아하 모먼트 후보가 둘이다. 하나를 고르는 게 아니라 둘 다 재고 비교한다.

     ① 회사의 첫 N건 운행 — 누가 기록했는지는 상관없다
        「첫 5건」이 현재 가설이다. 관리자가 5건을 다 했든 직원이 했든,
        회사 계정에 운행이 5건 쌓였다는 사실이 전환점이라는 것이다.
        기준이 3건이나 10건으로 바뀔 수 있어 N을 넷 다 계산해 둔다.
        원천 운행을 다 갖고 있으므로 다른 N이 필요해져도 여기만 고치면 된다.

     ② 관리자가 아닌 첫 직원의 운행 — 2단계 진입
        days_to_member_trip. 확산이 일어난 시점이다.

     둘은 배타적이지 않다. ①이 도달 속도를, ②가 확산 여부를 말한다.
     어느 쪽이 갱신·이탈과 더 붙는지는 90_check.sql 19번이 비교한다.

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

/* 회사의 N번째 운행이 언제였나. 누가 기록했는지는 보지 않는다.
   ※ ORDER BY 에 trip_id 를 마지막에 둔다.
     날짜와 시각만으로 정렬하면 같은 시각의 운행에서 순위가 실행마다 달라진다.
     signup_90days 에서 정렬키 4개가 모두 동점이라 세 번 실행에 세 번 다른
     계정이 남은 적이 있다. 결정적 tiebreak 가 없으면 숫자가 흔들린다. */
trip_rank AS (
  SELECT
    company_seq, trip_date,
    ROW_NUMBER() OVER (PARTITION BY company_seq
                       ORDER BY trip_date, start_time, trip_id) AS rn
  FROM `carbiz-6f7fc.cartax_statistics.view_trip`
  WHERE trip_date >= '2016-01-01'
    AND is_countable
),

trip_nth AS (
  SELECT
    company_seq,
    MIN(IF(rn =  1, trip_date, NULL))                 AS trip_1_date,
    MIN(IF(rn =  3, trip_date, NULL))                 AS trip_3_date,
    MIN(IF(rn =  5, trip_date, NULL))                 AS trip_5_date,
    MIN(IF(rn = 10, trip_date, NULL))                 AS trip_10_date
  FROM trip_rank
  WHERE rn <= 10
  GROUP BY company_seq
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

    /* ── 회사 기준 운행 이정표 — 누가 했는지 상관없다 ── */
    n.trip_1_date,
    n.trip_3_date,
    n.trip_5_date,
    n.trip_10_date,

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
  LEFT JOIN trip_nth       n  USING (company_seq)
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

  /* ── 회사 기준 도달 속도 ───────────────────────────────────────────
     아하 모먼트 후보 ①. 누가 기록했는지는 보지 않는다.
     현재 가설은 5건이지만 기준이 바뀔 수 있어 넷 다 둔다.                   */
  DATE_DIFF(b.trip_1_date,  b.signup_date, DAY)      AS days_to_trip_1,
  DATE_DIFF(b.trip_3_date,  b.signup_date, DAY)      AS days_to_trip_3,
  DATE_DIFF(b.trip_5_date,  b.signup_date, DAY)      AS days_to_trip_5,
  DATE_DIFF(b.trip_10_date, b.signup_date, DAY)      AS days_to_trip_10,

  /* 현재 기준의 아하 모먼트 도달 여부. 기준이 바뀌면 여기 한 줄만 고친다 */
  (b.trip_5_date IS NOT NULL)                        AS reached_aha,

  /* ── 단계별 소요일 ─────────────────────────────────────────────────
     아하 모먼트 후보 ②. 확산이 일어난 시점이다.                            */
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
