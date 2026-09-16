/* ============================================================================
   11. company_daily — 기업별 일별 상태 스냅샷
   ----------------------------------------------------------------------------
   설계안 03번의 「파생」 층. 원천에서 매일 만들어 쌓는다.

   ★ 왜 필요한가 — 원천만으로는 과거 상태를 알 수 없다.

     운행·결제·로그인은 사건이라 행으로 남는다. 「작년 3월 운행 수」는 WHERE 한 줄이다.
     하지만 company / user / department / purpose 는 MERGE 가 덮어쓴다.
     오늘 요금제가 premium 이면 어제도 premium 이었는지 알 방법이 없다.
     (company_pay_state 만 History 테이블이 따로 있어 예외다.)

     이 테이블이 없으면 다음이 전부 불가능하다.
       「작년 3월 말 기준 유료 기업 수」
       「이 회사가 언제 free 에서 plus 로 올라갔나」
       현재 운영 중인 월별 리포트를 새 구조로 옮기는 것

   ★ 이 파일에는 DROP TABLE 이 없다. 일부러 없다.
     이 테이블은 원천에서 다시 만들 수 없다. 지우면 과거 상태가 영구히 사라진다.
     (운행·결제와 달리 원본 DB 에도 어제 상태가 남아 있지 않다.)
     스키마를 바꿔야 하면 ALTER TABLE ADD COLUMN 을 쓴다.

   [실행]
     03_merge_daily.sql 이 끝난 뒤에 돌린다. raw_* 가 최신이어야 한다.
     같은 날짜로 다시 돌려도 안전하다 — 해당 날짜를 지우고 다시 넣는다.

   [비용]
     누적 활동을 매일 전량 재계산한다. 현재 운행 4.7 GB 기준 하루 약 $0.03,
     5년 뒤 21.7 GB 기준 하루 약 $0.11 이다.

     「전일 누적 + 당일 증분」이 더 싸지만 쓰지 않는다. 우리 증분 적재는
     updateTime 기준이라 3일 전 운행이 오늘 들어올 수 있고, 그러면 누적이
     조용히 어긋난다. 그 어긋남은 아무 에러도 내지 않는다.
     비용 차이가 연 $40 수준이므로 매일 다시 세는 쪽을 택한다.
   ========================================================================= */

/* DECLARE 는 스크립트 맨 앞에만 올 수 있다. 그래서 테이블 생성보다 먼저 둔다.
   덕분에 이 파일 전체가 멱등해져서 예약 쿼리 본문으로 그대로 쓸 수 있다 —
   테이블이 있으면 CREATE 는 아무것도 하지 않는다. */
DECLARE target_dt DATE DEFAULT DATE_SUB(CURRENT_DATE("Asia/Seoul"), INTERVAL 1 DAY);
--DECLARE target_dt DATE DEFAULT DATE('2026-09-16');   -- 소급 적재용 (주석 해제)

DECLARE inserted_cnt INT64 DEFAULT 0;

CREATE TABLE IF NOT EXISTS `carbiz-6f7fc.cartax_statistics.company_daily`
(
  snapshot_date            DATE     NOT NULL,
  company_seq              INT64    NOT NULL,
  company_code             STRING,

  /* ── 상태 — 덮어써서 사라지는 것들 ──────────────────────────────── */
  company_name             STRING,
  company_name_norm        STRING,   -- 정규화 규칙이 바뀌면 이후 스냅샷만 달라진다
  company_number_norm      STRING,
  business_type            STRING,
  plan_level               INT64,
  plan_name                STRING,
  enabled_state            STRING,   -- Y사용 N미사용 X탈퇴
  is_withdrawn             BOOL,
  is_test_account          BOOL,     -- 판정 키워드가 늘면 이후 스냅샷만 달라진다
  license_count            INT64,
  pay_method               STRING,
  is_auto_pay              BOOL,
  pay_cycle                STRING,
  contract_begin_date      DATE,
  contract_end_date        DATE,
  days_to_contract_end     INT64,
  is_trial_active          BOOL,
  trial_end_date           DATE,
  trial_cancel_date        DATE,
  setting_save_map_point   STRING,
  setting_privacy_mode     STRING,
  has_restricted_logging   BOOL,

  /* ── 사용자·부서 — raw_user 가 덮어써진다 ──────────────────────── */
  user_count_total         INT64,
  user_count_active        INT64,
  user_count_pending       INT64,
  user_count_withdrawn     INT64,
  user_count_admin         INT64,
  user_count_member_active INT64,
  department_count         INT64,

  /* ── 누적 활동 — 차분의 재료 ───────────────────────────────────────
     「최근 2주 운행 수」는 누적(오늘) − 누적(14일 전)이다.
     누적값만 있으면 7일·30일·90일 어떤 구간이든 만든다.                    */
  trip_count_total         INT64,
  trip_distance_total      INT64,
  admin_trip_count_total   INT64,
  member_trip_count_total  INT64,
  first_trip_date          DATE,
  last_trip_date           DATE,

  admin_login_count_total  INT64,
  app_login_count_total    INT64,
  admin_first_login_date   DATE,
  admin_last_login_date    DATE,
  app_first_login_date     DATE,
  app_last_login_date      DATE,

  payment_count_total      INT64,
  payment_amount_total     INT64,
  first_payment_date       DATE,
  last_payment_date        DATE,

  loaded_at                TIMESTAMP
)
PARTITION BY snapshot_date
CLUSTER BY company_seq, company_code
OPTIONS (
  description = '기업별 일별 상태 스냅샷. 원천에서 다시 만들 수 없다 — 지우면 과거 상태가 영구히 사라진다. DROP 금지.'
);


/* ==========================================================================
   일별 적재
   ========================================================================== */
BEGIN

  /* 같은 날짜로 다시 돌려도 안전하게. 지우고 다시 넣는다 */
  DELETE FROM `carbiz-6f7fc.cartax_statistics.company_daily`
  WHERE snapshot_date = target_dt;

  INSERT INTO `carbiz-6f7fc.cartax_statistics.company_daily`
  WITH
  /* 운행 누적. 스냅샷 기준일까지만 센다 — 나중에 소급 적재해도 같은 값이 나온다 */
  trip AS (
    SELECT
      company_seq,
      COUNT(*)                                        AS trip_count_total,
      SUM(IFNULL(distance, 0))                        AS trip_distance_total,
      COUNTIF(is_admin_created)                       AS admin_trip_count_total,
      COUNTIF(NOT is_admin_created)                   AS member_trip_count_total,
      MIN(trip_date)                                  AS first_trip_date,
      MAX(trip_date)                                  AS last_trip_date
    FROM `carbiz-6f7fc.cartax_statistics.view_trip`
    WHERE trip_date >= '2016-01-01' AND trip_date <= target_dt
      AND is_countable
    GROUP BY company_seq
  ),

  /* 관리자 콘솔 로그인 */
  la AS (
    SELECT
      company_seq,
      COUNTIF(is_success)                             AS admin_login_count_total,
      MIN(IF(is_success, DATE(created_at), NULL))     AS admin_first_login_date,
      MAX(IF(is_success, DATE(created_at), NULL))     AS admin_last_login_date
    FROM `carbiz-6f7fc.cartax_statistics.raw_login_admin`
    WHERE created_at >= '2016-01-01'
      AND DATE(created_at) <= target_dt
    GROUP BY company_seq
  ),

  /* 앱 로그인. company_seq 가 없어 raw_user 로 잇는다 */
  app AS (
    SELECT
      u.company_seq,
      COUNT(*)                                        AS app_login_count_total,
      MIN(DATE(a.created_at))                         AS app_first_login_date,
      MAX(DATE(a.created_at))                         AS app_last_login_date
    FROM `carbiz-6f7fc.cartax_statistics.raw_login_app` a
    JOIN (SELECT user_uid, company_seq
          FROM `carbiz-6f7fc.cartax_statistics.raw_user`
          WHERE user_uid IS NOT NULL AND company_seq IS NOT NULL) u
      USING (user_uid)
    WHERE a.created_at >= '2016-01-01'
      AND DATE(a.created_at) <= target_dt
    GROUP BY u.company_seq
  ),

  /* 결제. 환불을 뺀 순매출로 센다 */
  pay AS (
    SELECT
      company_seq,
      COUNTIF(result = 'success')                     AS payment_count_total,
      SUM(IF(result = 'success', net_amount, 0))      AS payment_amount_total,
      MIN(IF(result = 'success', event_date, NULL))   AS first_payment_date,
      MAX(IF(result = 'success', event_date, NULL))   AS last_payment_date
    FROM `carbiz-6f7fc.cartax_statistics.view_payment`
    WHERE source = 'payment' AND event_date <= target_dt
    GROUP BY company_seq
  )

  SELECT
    target_dt                                         AS snapshot_date,
    c.company_seq,
    c.company_code,

    c.company_name,
    c.company_name_norm,
    c.company_number_norm,
    c.business_type,
    c.plan_level,
    c.plan_name,
    c.enabled_state,
    c.is_withdrawn,
    c.is_test_account,
    c.license_count,
    c.pay_method,
    c.is_auto_pay,
    c.pay_cycle,
    c.contract_begin_date,
    c.contract_end_date,
    /* 뷰의 days_to_contract_end 는 오늘 기준이다. 스냅샷은 기준일로 다시 센다 */
    DATE_DIFF(c.contract_end_date, target_dt, DAY)    AS days_to_contract_end,
    c.is_trial_active,
    c.trial_end_date,
    c.trial_cancel_date,
    c.setting_save_map_point,
    c.setting_privacy_mode,
    c.has_restricted_logging,

    IFNULL(u.user_count_total, 0)                     AS user_count_total,
    IFNULL(u.user_count_active, 0)                    AS user_count_active,
    IFNULL(u.user_count_pending, 0)                   AS user_count_pending,
    IFNULL(u.user_count_withdrawn, 0)                 AS user_count_withdrawn,
    IFNULL(u.user_count_admin, 0)                     AS user_count_admin,
    IFNULL(u.user_count_member_active, 0)             AS user_count_member_active,
    IFNULL(u.department_count, 0)                     AS department_count,

    IFNULL(t.trip_count_total, 0)                     AS trip_count_total,
    IFNULL(t.trip_distance_total, 0)                  AS trip_distance_total,
    IFNULL(t.admin_trip_count_total, 0)               AS admin_trip_count_total,
    IFNULL(t.member_trip_count_total, 0)              AS member_trip_count_total,
    t.first_trip_date,
    t.last_trip_date,

    IFNULL(la.admin_login_count_total, 0)             AS admin_login_count_total,
    IFNULL(app.app_login_count_total, 0)              AS app_login_count_total,
    la.admin_first_login_date,
    la.admin_last_login_date,
    app.app_first_login_date,
    app.app_last_login_date,

    IFNULL(p.payment_count_total, 0)                  AS payment_count_total,
    IFNULL(p.payment_amount_total, 0)                 AS payment_amount_total,
    p.first_payment_date,
    p.last_payment_date,

    CURRENT_TIMESTAMP()                               AS loaded_at
  FROM `carbiz-6f7fc.cartax_statistics.view_company` c
  LEFT JOIN `carbiz-6f7fc.cartax_statistics.view_user_company` u USING (company_seq)
  LEFT JOIN trip t   USING (company_seq)
  LEFT JOIN la       USING (company_seq)
  LEFT JOIN app      USING (company_seq)
  LEFT JOIN pay p    USING (company_seq);

  SET inserted_cnt = @@row_count;

  INSERT INTO `carbiz-6f7fc.cartax_statistics.query_run_log`
  VALUES (target_dt, 'company_daily_snapshot', 'company_daily',
          IF(inserted_cnt = 0, 'EMPTY', 'SUCCESS'),
          inserted_cnt, CAST(NULL AS INT64), CAST(NULL AS STRING), CURRENT_TIMESTAMP());

EXCEPTION WHEN ERROR THEN
  INSERT INTO `carbiz-6f7fc.cartax_statistics.query_run_log`
  VALUES (target_dt, 'company_daily_snapshot', 'company_daily', 'FAIL',
          CAST(NULL AS INT64), CAST(NULL AS INT64),
          @@error.message, CURRENT_TIMESTAMP());
  RAISE USING MESSAGE = @@error.message;
END;
