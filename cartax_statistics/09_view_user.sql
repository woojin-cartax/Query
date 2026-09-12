/* ============================================================================
   09. view_user_company — 기업별 사용자·부서 요약
   ----------------------------------------------------------------------------
   설계안 05번의 user_count 가 여기서 나온다. 그런데 「사용자 수」가 하나가 아니다.
   상태에 따라 완전히 다른 숫자이고, 섞으면 이탈 판정이 틀어진다.

     user_count_total     행 전체. 탈퇴·정지 포함. 규모 파악용
     user_count_active    enabled='Y'(승인). 실제로 쓸 수 있는 사람
     user_count_pending   enabled='N'(미승인). 초대했는데 안 들어온 사람
     user_count_withdrawn enabled='X'(탈퇴)

   90일 스냅샷의 user_count 가 어느 것인지 확인해야 한다. 대조 시 이 셋을
   다 맞춰 보고 어느 것과 일치하는지 본다.

   ★ 관리자와 사용자를 나눈다. role_seq = 0 이 최고관리자이고 나머지는 전부
     사용자다 (2026-09-12 확인). 판정은 04_udf.sql 의 is_super_admin() 한 곳에만 둔다.

     08_view_login.sql 의 is_admin_only 와는 다른 것이다. 섞지 않는다.
       여기(09)   권한상 관리자가 몇 명인가          — 명부 기준
       저기(08)   관리자 콘솔에 실제로 들어왔는가    — 행동 기준
     둘이 어긋나면(관리자 권한은 있는데 콘솔에 안 들어온다) 그 자체가 신호다.
   ========================================================================= */

CREATE OR REPLACE VIEW `carbiz-6f7fc.cartax_statistics.view_user_company` AS
WITH u AS (
  SELECT
    company_seq,
    COUNT(*)                                          AS user_count_total,
    COUNTIF(enabled_state = 'Y')                      AS user_count_active,
    COUNTIF(enabled_state = 'N')                      AS user_count_pending,
    COUNTIF(enabled_state = 'X')                      AS user_count_withdrawn,
    COUNTIF(enabled_state = 'B')                      AS user_count_suspended,
    COUNTIF(enabled_state = 'C')                      AS user_count_device_change,

    /* 관리자 / 사용자. role_seq = 0 이 최고관리자다 */
    COUNTIF(`carbiz-6f7fc.cartax_statistics`.is_super_admin(role_seq))
                                                      AS user_count_admin,
    COUNTIF(NOT `carbiz-6f7fc.cartax_statistics`.is_super_admin(role_seq))
                                                      AS user_count_member,
    /* 승인된 사용자 중에서만. 탈퇴·미승인을 빼고 실제 인원을 본다 */
    COUNTIF(enabled_state = 'Y'
            AND NOT `carbiz-6f7fc.cartax_statistics`.is_super_admin(role_seq))
                                                      AS user_count_member_active,

    /* 확산 속도. 첫 사용자와 마지막 사용자의 간격 */
    MIN(created_at)                                   AS first_user_created_at,
    MAX(created_at)                                   AS last_user_created_at,

    /* 최근 90일에 새로 들어온 사용자. 확장 중인지 정체인지 */
    COUNTIF(created_at >= DATETIME_SUB(CURRENT_DATETIME("Asia/Seoul"), INTERVAL 90 DAY))
                                                      AS user_added_90d,

    /* 이메일 도메인 구성. 포털 도메인만 쓰면 회사 도메인이 없는 소규모다 */
    COUNT(DISTINCT email_domain)                      AS email_domain_count,
    COUNTIF(email_domain IN ('naver.com','gmail.com','daum.net','hanmail.net',
                             'nate.com','kakao.com','outlook.com','hotmail.com',
                             'yahoo.com','icloud.com'))
                                                      AS user_portal_email
  FROM `carbiz-6f7fc.cartax_statistics.raw_user`
  GROUP BY company_seq
),

d AS (
  SELECT
    company_seq,
    COUNT(*)                                          AS department_count,
    MAX(depth)                                        AS department_max_depth
  FROM `carbiz-6f7fc.cartax_statistics.raw_department`
  GROUP BY company_seq
)

SELECT
  c.company_seq,
  c.company_code,
  c.company_name,
  c.plan_name,
  c.is_withdrawn,
  c.signup_date_d,
  c.license_count,

  IFNULL(u.user_count_total, 0)         AS user_count_total,
  IFNULL(u.user_count_active, 0)        AS user_count_active,
  IFNULL(u.user_count_pending, 0)       AS user_count_pending,
  IFNULL(u.user_count_withdrawn, 0)     AS user_count_withdrawn,
  IFNULL(u.user_count_suspended, 0)     AS user_count_suspended,
  IFNULL(u.user_count_device_change, 0) AS user_count_device_change,
  IFNULL(u.user_count_admin, 0)         AS user_count_admin,
  IFNULL(u.user_count_member, 0)        AS user_count_member,
  IFNULL(u.user_count_member_active, 0) AS user_count_member_active,
  u.first_user_created_at,
  u.last_user_created_at,
  IFNULL(u.user_added_90d, 0)           AS user_added_90d,
  IFNULL(u.email_domain_count, 0)       AS email_domain_count,
  IFNULL(u.user_portal_email, 0)        AS user_portal_email,

  IFNULL(d.department_count, 0)         AS department_count,
  IFNULL(d.department_max_depth, 0)     AS department_max_depth,

  /* ── 판정 ──────────────────────────────────────────────────────────
     라이선스를 산 만큼 쓰고 있나. 1을 넘으면 초과, 낮으면 놀고 있는 것이다.
     낮은 채로 갱신일이 오면 감축 위험이고, 1을 넘으면 업셀 기회다. */
  SAFE_DIVIDE(u.user_count_active, NULLIF(c.license_count, 0))
                                        AS license_fill_rate,

  /* 관리자 1명당 사용자 수. 조직 규모의 대리 지표 */
  SAFE_DIVIDE(u.user_count_member_active, NULLIF(u.user_count_admin, 0))
                                        AS member_per_admin,

  /* 초대는 했는데 안 들어온 비율. 온보딩이 막힌 지점이다 */
  SAFE_DIVIDE(u.user_count_pending, NULLIF(u.user_count_total, 0))
                                        AS pending_rate,

  /* 회사 도메인 없이 포털 이메일만 쓰나. 소규모·비공식 도입 신호 */
  (IFNULL(u.user_count_total, 0) > 0
   AND u.user_portal_email = u.user_count_total)
                                        AS is_portal_email_only,

  /* 부서를 만들었나. 조직 구조를 넣었다는 것은 도입이 진행됐다는 뜻이다 */
  (IFNULL(d.department_count, 0) > 0)   AS has_department,

  /* 관리자 말고 쓰는 사람이 있나. 없으면 도입이 확산되지 않은 것이다.
     08번의 is_admin_only(콘솔 로그인 기준)와 다른 각도다 — 이건 명부 기준이다 */
  (IFNULL(u.user_count_member_active, 0) > 0) AS has_member_user

FROM `carbiz-6f7fc.cartax_statistics.view_company` c
LEFT JOIN u USING (company_seq)
LEFT JOIN d USING (company_seq);
