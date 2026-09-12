/* ============================================================================
   07. view_login_company — 기업별 로그인 요약
   ----------------------------------------------------------------------------
   설계안 05번에서 「받아야 한다」고 썼던 것들이 여기서 계산된다.
     pc_first_login_date · pc_last_login_date · pc_login_count_total
     has_app_login
   받을 필요가 없어졌다.

   그 이상으로 원천에만 있는 것이 둘 있다.

   ① 로그인 실패
      login_pc.is_success = FALSE + error_message.
      실패가 반복되는 기업은 제품이 불만인 게 아니라 들어오질 못하고 있다.
      이탈 원인 분류가 갈린다.

   ② 사용자 확산
      로그인한 사용자 수를 센다. 관리자 1명만 쓰는 회사와 직원까지 쓰는 회사는
      완전히 다른 고객이다.
      ※ 이건 「등록 사용자 수」가 아니라 「실제 로그인한 사용자 수」다.
        user 테이블이 없어 등록 수를 셀 수 없다. 둘을 섞어 쓰면 안 된다.

   ※ 앱 로그인(login_app)에는 company_seq 가 없다. uid 뿐이다.
     여기서는 운행 기록으로 uid → 기업을 잇는다. 운행을 한 번도 안 한 사용자는
     빠진다. 임시 방편이고, user 테이블을 받으면 그걸로 바꾼다.

   ※ raw_login_pc / raw_login_app / raw_trip 모두 파티션 테이블이다.
     이 뷰는 전 기간을 훑는다. 대시보드에서 매번 호출하면 비싸다.
     자주 쓰게 되면 뷰가 아니라 테이블로 굳힌다 (설계안 03번의 「캐시」).
   ========================================================================= */

CREATE OR REPLACE VIEW `carbiz-6f7fc.source_db.view_login_company` AS
WITH
/* uid → 기업. 운행 기록에서 끌어온다. user 테이블이 오면 이 CTE 를 갈아끼운다 */
uid_company AS (
  SELECT user_uid, company_seq
  FROM `carbiz-6f7fc.source_db.raw_trip`
  WHERE trip_date >= '2016-01-01'
    AND user_uid IS NOT NULL
  GROUP BY user_uid, company_seq
),

pc AS (
  SELECT
    company_seq,
    MIN(IF(is_success, created_at, NULL))              AS pc_first_login_at,
    MAX(IF(is_success, created_at, NULL))              AS pc_last_login_at,
    COUNTIF(is_success)                                AS pc_login_count,
    COUNTIF(NOT is_success)                            AS pc_login_fail_count,
    COUNT(DISTINCT IF(is_success, user_uid, NULL))     AS pc_active_user_count,

    /* 최근 30일 로그인. 활동 여부의 가장 단순한 신호다 */
    COUNTIF(is_success
            AND created_at >= DATETIME_SUB(CURRENT_DATETIME("Asia/Seoul"), INTERVAL 30 DAY))
                                                       AS pc_login_count_30d,

    /* 마지막 시도가 실패였나. 지금 막혀 있다는 뜻이다 */
    ARRAY_AGG(is_success ORDER BY created_at DESC LIMIT 1)[SAFE_OFFSET(0)]
                                                       AS pc_last_attempt_success,
    ARRAY_AGG(error_message IGNORE NULLS ORDER BY created_at DESC LIMIT 1)[SAFE_OFFSET(0)]
                                                       AS pc_last_error_message
  FROM `carbiz-6f7fc.source_db.raw_login_pc`
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
  FROM `carbiz-6f7fc.source_db.raw_login_app` a
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
  pc.pc_first_login_at,
  pc.pc_last_login_at,
  IFNULL(pc.pc_login_count, 0)        AS pc_login_count,
  IFNULL(pc.pc_login_count_30d, 0)    AS pc_login_count_30d,
  IFNULL(pc.pc_login_fail_count, 0)   AS pc_login_fail_count,
  IFNULL(pc.pc_active_user_count, 0)  AS pc_active_user_count,
  pc.pc_last_attempt_success,
  pc.pc_last_error_message,

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

  /* 로그인한 사용자 수. 등록 사용자 수가 아니다 — user 테이블이 없다.
     PC 와 앱 중 큰 쪽을 쓴다. 두 uid 집합이 겹치는지 확인되지 않았다. */
  GREATEST(IFNULL(pc.pc_active_user_count, 0),
           IFNULL(app.app_active_user_count, 0))       AS active_user_count,

  /* 관리자 혼자 쓰나. 확산이 안 된 상태다 */
  (GREATEST(IFNULL(pc.pc_active_user_count, 0),
            IFNULL(app.app_active_user_count, 0)) <= 1) AS is_single_user,

  /* 지금 막혀 있나. 마지막 시도가 실패였고 성공 이력이 있는 경우 */
  (pc.pc_last_attempt_success = FALSE
   AND IFNULL(pc.pc_login_count, 0) > 0)               AS is_login_blocked,

  /* 마지막 로그인 이후 경과일. PC·앱 중 더 최근 것 기준 */
  DATE_DIFF(
    CURRENT_DATE("Asia/Seoul"),
    DATE(GREATEST(IFNULL(pc.pc_last_login_at,  DATETIME '1970-01-01'),
                  IFNULL(app.app_last_login_at, DATETIME '1970-01-01'))),
    DAY)                                               AS days_since_last_login

FROM `carbiz-6f7fc.source_db.view_company` c
LEFT JOIN pc  USING (company_seq)
LEFT JOIN app USING (company_seq);
