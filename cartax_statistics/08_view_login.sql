/* ============================================================================
   08. view_login_company — 기업별 로그인 요약
   ----------------------------------------------------------------------------
   설계안 05번에서 「받아야 한다」고 썼던 것들이 여기서 계산된다.
     pc_first_login_date · pc_last_login_date · admin_login_count_total
     has_app_login
   받을 필요가 없어졌다.

   그 이상으로 원천에만 있는 것이 둘 있다.

   ① 로그인 실패
      login_admin.is_success = FALSE + error_message.
      실패가 반복되는 기업은 제품이 불만인 게 아니라 들어오질 못하고 있다.
      이탈 원인 분류가 갈린다.

   ② 사용자 확산
      관리자 1명만 쓰는 회사와 직원까지 쓰는 회사는 완전히 다른 고객이다.
      등록 사용자 수는 09_view_user.sql 에서 센다. 여기서는 실제 로그인한
      사용자 수를 센다. 둘은 다른 값이고 섞어 쓰면 안 된다.

   ★ 두 로그인은 성격이 다르다. 합쳐 세지 않는다.
      login_admin  비즈 관리자 페이지 로그인. 관리자 계정(company.cid)이 주체
      login_app    앱 로그인. 직원(user.uid)이 주체
      관리자만 들어오는 회사와 직원까지 앱을 쓰는 회사가 갈린다.

   ※ login_app 에는 company_seq 가 없다. uid 뿐이라 raw_user 로 잇는다.
     (user 테이블이 오기 전에는 운행 기록으로 이었고, 운행을 한 번도 안 한
      사용자가 빠졌다. 이제 그 누락이 없다.)

   ※ raw_login_admin / raw_login_app / raw_trip 모두 파티션 테이블이다.
     이 뷰는 전 기간을 훑는다. 대시보드에서 매번 호출하면 비싸다.
     자주 쓰게 되면 뷰가 아니라 테이블로 굳힌다 (설계안 03번의 「캐시」).
   ========================================================================= */

CREATE OR REPLACE VIEW `carbiz-6f7fc.cartax_statistics.view_login_company` AS
WITH
/* uid → 기업. user 테이블이 원천이다 */
uid_company AS (
  SELECT user_uid, company_seq
  FROM `carbiz-6f7fc.cartax_statistics.raw_user`
  WHERE user_uid IS NOT NULL AND company_seq IS NOT NULL
),

pc AS (
  SELECT
    company_seq,
    MIN(IF(is_success, created_at, NULL))              AS admin_first_login_at,
    MAX(IF(is_success, created_at, NULL))              AS admin_last_login_at,
    COUNTIF(is_success)                                AS admin_login_count,
    COUNTIF(NOT is_success)                            AS admin_login_fail_count,
    COUNT(DISTINCT IF(is_success, admin_cid, NULL))    AS admin_account_count,

    /* 최근 30일 로그인. 활동 여부의 가장 단순한 신호다 */
    COUNTIF(is_success
            AND created_at >= DATETIME_SUB(CURRENT_DATETIME("Asia/Seoul"), INTERVAL 30 DAY))
                                                       AS admin_login_count_30d,

    /* 마지막 시도가 실패였나. 지금 막혀 있다는 뜻이다 */
    ARRAY_AGG(is_success ORDER BY created_at DESC LIMIT 1)[SAFE_OFFSET(0)]
                                                       AS admin_last_attempt_success,
    ARRAY_AGG(error_message IGNORE NULLS ORDER BY created_at DESC LIMIT 1)[SAFE_OFFSET(0)]
                                                       AS admin_last_error_message
  FROM `carbiz-6f7fc.cartax_statistics.raw_login_admin`
  WHERE created_at >= '2016-01-01'
  GROUP BY company_seq
),

app AS (
  SELECT
    u.company_seq,
    MIN(a.created_at)                                  AS app_first_login_at,
    MAX(a.created_at)                                  AS app_last_login_at,
    COUNT(*)                                           AS app_login_count,
    COUNT(DISTINCT a.user_uid)                         AS app_active_user_count,
    COUNT(DISTINCT a.device_id)                        AS app_device_count,
    COUNTIF(a.created_at >= DATETIME_SUB(CURRENT_DATETIME("Asia/Seoul"), INTERVAL 30 DAY))
                                                       AS app_login_count_30d,

    /* 최신 앱 버전과 OS 분포. 버전 채택 추적 */
    ARRAY_AGG(a.app_version IGNORE NULLS ORDER BY a.created_at DESC LIMIT 1)[SAFE_OFFSET(0)]
                                                       AS app_latest_version,
    COUNTIF(a.os_type = 'iOS')                         AS app_login_ios,
    COUNTIF(a.os_type = 'Android')                     AS app_login_android
  FROM `carbiz-6f7fc.cartax_statistics.raw_login_app` a
  JOIN uid_company u USING (user_uid)
  WHERE a.created_at >= '2016-01-01'
  GROUP BY u.company_seq
)

SELECT
  c.company_seq,
  c.company_code,
  c.company_name,
  c.is_withdrawn,
  c.signup_date_d,

  /* ── PC ────────────────────────────────────────────────────────── */
  pc.admin_first_login_at,
  pc.admin_last_login_at,
  IFNULL(pc.admin_login_count, 0)        AS admin_login_count,
  IFNULL(pc.admin_login_count_30d, 0)    AS admin_login_count_30d,
  IFNULL(pc.admin_login_fail_count, 0)   AS admin_login_fail_count,
  IFNULL(pc.admin_account_count, 0)  AS admin_account_count,
  pc.admin_last_attempt_success,
  pc.admin_last_error_message,

  /* ── 앱 ────────────────────────────────────────────────────────── */
  app.app_first_login_at,
  app.app_last_login_at,
  IFNULL(app.app_login_count, 0)      AS app_login_count,
  IFNULL(app.app_login_count_30d, 0)  AS app_login_count_30d,
  IFNULL(app.app_active_user_count, 0) AS app_active_user_count,
  IFNULL(app.app_device_count, 0)     AS app_device_count,
  app.app_latest_version,
  IFNULL(app.app_login_ios, 0)        AS app_login_ios,
  IFNULL(app.app_login_android, 0)    AS app_login_android,

  /* ── 판정 ──────────────────────────────────────────────────────── */
  (IFNULL(app.app_login_count, 0) > 0)                 AS has_app_login,

  /* 앱에 로그인한 사용자 수. 등록 사용자 수가 아니다 (09번 뷰가 그걸 센다).
     관리자 계정 수와 합치지 않는다 — 주체가 다르다. */
  IFNULL(app.app_active_user_count, 0)                 AS active_app_user_count,

  /* 관리자만 들어오고 앱을 쓰는 직원이 없다. 확산이 안 된 상태다 */
  (IFNULL(app.app_active_user_count, 0) = 0
   AND IFNULL(pc.admin_login_count, 0) > 0)            AS is_admin_only,

  /* 지금 막혀 있나. 마지막 시도가 실패였고 성공 이력이 있는 경우 */
  (pc.admin_last_attempt_success = FALSE
   AND IFNULL(pc.admin_login_count, 0) > 0)               AS is_login_blocked,

  /* 마지막 로그인 이후 경과일. PC·앱 중 더 최근 것 기준 */
  DATE_DIFF(
    CURRENT_DATE("Asia/Seoul"),
    DATE(GREATEST(IFNULL(pc.admin_last_login_at,  DATETIME '1970-01-01'),
                  IFNULL(app.app_last_login_at, DATETIME '1970-01-01'))),
    DAY)                                               AS days_since_last_login

FROM `carbiz-6f7fc.cartax_statistics.view_company` c
LEFT JOIN pc  USING (company_seq)
LEFT JOIN app USING (company_seq);
