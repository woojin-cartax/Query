/* ============================================================================
   90. 점검 — 아무것도 바꾸지 않는다
   ----------------------------------------------------------------------------
   최초 적재 직후에 돌린다. 06번 뷰의 판정 세 가지가 전제대로인지 확인한다.
   어긋나면 뷰를 고친다. 확인 전에는 집계를 신뢰하지 않는다.
   ========================================================================= */

/* ── 1. 합치기·동승자 — 중복 집계 규모를 먼저 잰다 ─────────────────────
   merge_parent_seq > 0 인 행이 정말 자식인지, 그 부모가 실제로 있는지.
   부모가 없는 고아 자식이 많으면 06번의 제외 규칙이 운행을 통째로 버린다.   */
SELECT
  COUNTIF(IFNULL(merge_parent_seq,0) > 0)                    AS child_rows,
  COUNTIF(is_merge_parent)                                   AS parent_rows,
  COUNTIF(IFNULL(merge_parent_seq,0) > 0
          AND merge_parent_seq NOT IN (
            SELECT trip_id FROM `carbiz-6f7fc.cartax_statistics.raw_trip`
            WHERE trip_date >= '2016-01-01'))                AS orphan_child_rows,
  COUNTIF(overlap_state = 'REJECT')                          AS overlap_reject_rows,
  COUNTIF(overlap_state = 'OWN')                             AS overlap_own_rows,
  COUNT(*)                                                   AS total_rows
FROM `carbiz-6f7fc.cartax_statistics.raw_trip`
WHERE trip_date >= '2016-01-01';


/* ── 2. GPS 실운행 판정 ───────────────────────────────────────────────
   gps_distance = 0 인데 distance > 0 인 행이 수기 입력이라는 전제.
   이 비율이 지나치게 높으면 GPS 거리가 아예 안 채워지는 구간이 있는 것이다. */
SELECT
  EXTRACT(YEAR FROM trip_date)                               AS yr,
  COUNT(*)                                                   AS row_cnt,
  COUNTIF(IFNULL(gps_distance,0) > 0)                        AS gps_rows,
  ROUND(COUNTIF(IFNULL(gps_distance,0) > 0) / COUNT(*) * 100, 1) AS gps_pct,
  COUNTIF(IFNULL(gps_distance,0) = 0 AND IFNULL(distance,0) > 0) AS manual_rows
FROM `carbiz-6f7fc.cartax_statistics.raw_trip`
WHERE trip_date >= '2016-01-01'
GROUP BY yr ORDER BY yr;


/* ── 3. driving_type 실제 값 ──────────────────────────────────────────
   06번이 '수동' 이라는 문자열을 그대로 비교한다. 실제 값이 다르면 판정이 깨진다. */
SELECT driving_type, COUNT(*) AS row_cnt, COUNTIF(is_auto_start) AS auto_start_rows
FROM `carbiz-6f7fc.cartax_statistics.raw_trip`
WHERE trip_date >= '2016-01-01'
GROUP BY driving_type ORDER BY row_cnt DESC;


/* ── 4. plan_level 검증 ──────────────────────────────────────────────
   1=free / 2=plus / 3=premium 으로 확인됐다 (2026-09-12).
   실제 데이터가 그 전제와 맞는지 본다. free 인데 결제 수단이 CARD 이거나
   premium 인데 pay_method='FREE' 면 전제가 깨진 것이다.
   4 이상의 값이 나오면 새 등급이 생긴 것이니 04_udf.sql 을 고친다. */
SELECT
  c.plan_level,
  `carbiz-6f7fc.cartax_statistics`.plan_name(c.plan_level) AS plan_name,
  COUNT(*)                                          AS companies,
  COUNTIF(s.is_trial_active)                        AS trial_companies,
  COUNTIF(s.pay_method = 'FREE')                    AS pay_method_free,
  COUNTIF(s.pay_method = 'CARD')                    AS pay_method_card,
  COUNTIF(s.pay_method = 'TRANS')                   AS pay_method_trans,
  APPROX_QUANTILES(s.license_count, 4)              AS license_quartiles
FROM `carbiz-6f7fc.cartax_statistics.raw_company` c
LEFT JOIN `carbiz-6f7fc.cartax_statistics.raw_company_pay_state` s USING (company_seq)
GROUP BY c.plan_level ORDER BY c.plan_level;


/* ── 5. 사업자등록번호 확보율 ─────────────────────────────────────────
   언제부터 받기 시작했는지, 중복 판정을 얼마나 대체할 수 있는지 본다. */
SELECT
  EXTRACT(YEAR FROM signup_date)                             AS signup_year,
  COUNT(*)                                                   AS companies,
  COUNTIF(company_number IS NOT NULL AND company_number != '') AS has_number,
  ROUND(COUNTIF(company_number IS NOT NULL AND company_number != '')
        / COUNT(*) * 100, 1)                                 AS pct
FROM `carbiz-6f7fc.cartax_statistics.raw_company`
GROUP BY signup_year ORDER BY signup_year;


/* ── 6. 결제 실패 사유 — 자유 텍스트에 개인정보가 섞이는지 ────────────
   설계안 10-④. 실제 값을 보고 policy/30_data.md 를 채운다. */
SELECT error_message, COUNT(*) AS row_cnt
FROM `carbiz-6f7fc.cartax_statistics.raw_pay_schedule`
WHERE status = 'E' AND error_message IS NOT NULL
GROUP BY error_message ORDER BY row_cnt DESC LIMIT 50;


/* ── 7. createTime 이관 흔적 ─────────────────────────────────────────
   payment 샘플에서 seq 1~10 의 createTime 이 전부 2017-05-15 19:48:10 이었다.
   같은 값이 몇 건이나 뭉쳐 있는지 확인하고, 그 구간은 기간 분석에서 뺀다. */
SELECT DATE(created_at) AS created_date, COUNT(*) AS row_cnt,
       MIN(contract_begin_date) AS min_begin, MAX(contract_begin_date) AS max_begin
FROM `carbiz-6f7fc.cartax_statistics.raw_payment`
GROUP BY created_date ORDER BY row_cnt DESC LIMIT 10;


/* ── 8. 탈퇴 판정 — enabled 3값이 실제로 무엇인지 ─────────────────────
   90일 스냅샷에서는 탈퇴 컬럼이 없어 user_count = 0 을 대리지표로 썼다.
   이제 company.enabled 에 X(탈퇴)가 명시돼 있다. 대리지표가 필요 없다.

   다만 N(미사용)이 무엇인지 모른다. 관리자가 정지시킨 것인지,
   결제 만료로 내려간 것인지. X 와 N 을 묶으면 안 된다.
   활동 흔적과 교차해서 셋이 실제로 어떻게 다른지 본다. */
SELECT
  c.enabled_state,
  COUNT(*)                                          AS companies,
  COUNTIF(l.active_user_count = 0)                  AS no_active_user,
  COUNTIF(l.admin_login_count = 0 AND l.app_login_count = 0) AS never_logged_in,
  ROUND(AVG(l.days_since_last_login), 0)            AS avg_days_since_login,
  COUNTIF(s.contract_end_date < CURRENT_DATE("Asia/Seoul")) AS contract_expired,
  COUNTIF(s.is_auto_pay)                            AS auto_pay_on
FROM `carbiz-6f7fc.cartax_statistics.raw_company` c
LEFT JOIN `carbiz-6f7fc.cartax_statistics.view_login_company` l USING (company_seq)
LEFT JOIN `carbiz-6f7fc.cartax_statistics.raw_company_pay_state` s USING (company_seq)
GROUP BY c.enabled_state;


/* ── 9. referer 에 개인정보가 붙는지 ──────────────────────────────────
   유입 경로로 쓰려고 받는다. URL 쿼리 파라미터에 이메일·토큰이 실려 오면
   수집을 중단하거나 호스트만 남기도록 바꾼다. */
SELECT
  REGEXP_EXTRACT(referer, r'^https?://([^/]+)')     AS host,
  COUNT(*)                                          AS row_cnt,
  COUNTIF(REGEXP_CONTAINS(referer, r'[?&]'))        AS has_query_param,
  COUNTIF(REGEXP_CONTAINS(referer, r'@|token|email|passwd|pwd|key=')) AS looks_sensitive
FROM `carbiz-6f7fc.cartax_statistics.raw_login_admin`
WHERE created_at >= '2016-01-01' AND referer IS NOT NULL
GROUP BY host ORDER BY row_cnt DESC LIMIT 30;


/* ── 10. 로그인 이력 규모 ────────────────────────────────────────────
   앱 로그인은 앱 실행마다 남을 수 있다. 그러면 운행보다 클 수도 있다.
   증분 크기를 먼저 재고 파티션·클러스터가 맞는지 판단한다. */
SELECT 'login_admin' AS tbl, EXTRACT(YEAR FROM created_at) AS yr, COUNT(*) AS row_cnt
FROM `carbiz-6f7fc.cartax_statistics.raw_login_admin` WHERE created_at >= '2016-01-01'
GROUP BY yr
UNION ALL
SELECT 'login_app', EXTRACT(YEAR FROM created_at), COUNT(*)
FROM `carbiz-6f7fc.cartax_statistics.raw_login_app` WHERE created_at >= '2016-01-01'
GROUP BY 2
ORDER BY tbl, yr;


/* ── 11. PC 와 앱의 uid 가 같은 체계인가 ──────────────────────────────
   07번 뷰가 둘 중 큰 쪽을 사용자 수로 쓴다. 두 uid 집합이 아예 다른
   체계라면 그 계산이 틀린다. 겹침을 먼저 확인한다. */
WITH p AS (SELECT DISTINCT user_uid FROM `carbiz-6f7fc.cartax_statistics.raw_login_admin`
           WHERE created_at >= '2016-01-01' AND user_uid IS NOT NULL),
     a AS (SELECT DISTINCT user_uid FROM `carbiz-6f7fc.cartax_statistics.raw_login_app`
           WHERE created_at >= '2016-01-01' AND user_uid IS NOT NULL)
SELECT (SELECT COUNT(*) FROM p)                                  AS pc_uids,
       (SELECT COUNT(*) FROM a)                                  AS app_uids,
       (SELECT COUNT(*) FROM p JOIN a USING (user_uid))          AS both,
       (SELECT COUNT(*) FROM a WHERE user_uid NOT IN (SELECT user_uid FROM
          `carbiz-6f7fc.cartax_statistics.raw_trip` WHERE trip_date >= '2016-01-01'))
                                                                 AS app_uid_without_trip;


/* ── 12. 로그인 실패 사유 분포 ───────────────────────────────────────
   반복 실패가 이탈로 이어지는지 보려면 사유를 먼저 알아야 한다.
   errorMsg 에 개인정보가 섞이는지도 같이 본다. */
SELECT error_message, COUNT(*) AS row_cnt,
       COUNT(DISTINCT company_seq) AS companies
FROM `carbiz-6f7fc.cartax_statistics.raw_login_admin`
WHERE created_at >= '2016-01-01' AND NOT is_success
GROUP BY error_message ORDER BY row_cnt DESC LIMIT 30;


/* ── 13. role_seq 가 무엇인가 ────────────────────────────────────────
   관리자 여부를 여기서 판정하고 싶은데 role 테이블이 없다.
   값의 분포와, 비즈 관리자 페이지 로그인 여부의 상관을 본다.
   특정 role_seq 가 관리자 로그인과 강하게 붙으면 그것이 관리자 권한이다. */
SELECT
  u.role_seq,
  COUNT(*)                                          AS users,
  COUNT(DISTINCT u.company_seq)                     AS companies,
  COUNTIF(u.is_secondary)                           AS secondary_users,
  COUNTIF(u.is_developer)                           AS developer_users,
  COUNTIF(a.user_uid IS NOT NULL)                   AS has_admin_login
FROM `carbiz-6f7fc.cartax_statistics.raw_user` u
LEFT JOIN (
  SELECT DISTINCT user_uid FROM `carbiz-6f7fc.cartax_statistics.raw_login_admin`
  WHERE created_at >= '2016-01-01' AND is_success AND user_uid IS NOT NULL
) a USING (user_uid)
GROUP BY u.role_seq ORDER BY users DESC LIMIT 30;


/* ── 14. 사용자 수 — 90일 스냅샷과 어느 정의가 맞는가 ─────────────────
   user_count 가 하나가 아니다. 전체 / 승인 / 미승인 / 탈퇴가 다 다른 숫자다.
   기존 signup_90days 의 user_count 가 어느 것인지 맞춰 본다.
   대조가 끝나기 전에는 두 시스템의 사용자 수를 같은 것으로 보지 않는다. */
SELECT
  v.company_code,
  v.user_count_total,
  v.user_count_active,
  v.user_count_pending,
  v.user_count_withdrawn,
  s.user_count                                      AS snapshot_user_count,
  v.user_count_total   - s.user_count               AS diff_total,
  v.user_count_active  - s.user_count               AS diff_active
FROM `carbiz-6f7fc.cartax_statistics.view_user_company` v
JOIN (
  SELECT company_code, user_count
  FROM `carbiz-6f7fc.signup_90days.view_signup_90days_latest`
) s USING (company_code)
WHERE v.user_count_total != s.user_count
ORDER BY ABS(v.user_count_active - s.user_count) DESC LIMIT 50;


/* ── 15. 부서명에 사람 이름이 섞이는지 ───────────────────────────────
   부서명은 개인정보가 아니지만 소규모 회사에서 「홍길동팀」처럼 들어올 수 있다.
   한글 2~3자 + 팀/파트 패턴을 세어 규모를 가늠한다. */
SELECT
  COUNT(*)                                          AS departments,
  COUNTIF(REGEXP_CONTAINS(department_name, r'^[가-힣]{2,4}(팀|파트|님|씨)$')) AS looks_personal,
  COUNTIF(depth = 0)                                AS root_departments,
  MAX(depth)                                        AS max_depth
FROM `carbiz-6f7fc.cartax_statistics.raw_department`;
