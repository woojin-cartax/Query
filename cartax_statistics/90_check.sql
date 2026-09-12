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


/* ── 13. 관리자 판정 검증 ────────────────────────────────────────────
   role_seq = 0 이 최고관리자다 (2026-09-12 확인).
   실제로 그런지 두 가지로 본다.

   ① role_seq = 0 인 사용자가 비즈 관리자 페이지에 로그인하는가
      권한이 맞다면 has_admin_login 비율이 0 그룹에서 압도적으로 높아야 한다.
   ② role_seq = 0 이 아닌데 관리자 콘솔에 들어오는 사용자가 있는가
      있으면 0 말고 다른 관리자 등급이 있다는 뜻이다. 그때 UDF 를 고친다.

   ※ role_seq 가 NULL 인 사용자도 센다. is_super_admin() 이 NULL 을 FALSE 로
     떨어뜨리므로 그들은 조용히 「사용자」로 분류된다. 규모를 알아야 한다. */
SELECT
  CASE WHEN u.role_seq IS NULL THEN 'NULL'
       WHEN u.role_seq = 0     THEN '0 (최고관리자)'
       ELSE CAST(u.role_seq AS STRING) END            AS role_seq,
  COUNT(*)                                            AS users,
  COUNT(DISTINCT u.company_seq)                       AS companies,
  COUNTIF(u.enabled_state = 'Y')                      AS active_users,
  COUNTIF(a.user_uid IS NOT NULL)                     AS has_admin_login,
  ROUND(COUNTIF(a.user_uid IS NOT NULL) / COUNT(*) * 100, 1) AS admin_login_pct
FROM `carbiz-6f7fc.cartax_statistics.raw_user` u
LEFT JOIN (
  SELECT DISTINCT user_uid FROM `carbiz-6f7fc.cartax_statistics.raw_login_admin`
  WHERE created_at >= '2016-01-01' AND is_success AND user_uid IS NOT NULL
) a USING (user_uid)
GROUP BY 1 ORDER BY users DESC LIMIT 30;


/* ── 13b. 관리자가 0명인 기업 ────────────────────────────────────────
   모든 기업에 최고관리자가 최소 1명은 있어야 한다. 0 이면 판정이 틀렸거나
   role_seq 체계가 기업마다 다른 것이다. 숫자가 크면 UDF 를 다시 본다. */
SELECT
  COUNTIF(user_count_admin = 0)                       AS companies_without_admin,
  COUNTIF(user_count_admin = 1)                       AS companies_with_one_admin,
  COUNTIF(user_count_admin >= 2)                      AS companies_with_many_admins,
  COUNTIF(NOT has_member_user)                        AS companies_admin_only,
  COUNT(*)                                            AS companies
FROM `carbiz-6f7fc.cartax_statistics.view_user_company`;


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


/* ── 15. 부서 구조 ───────────────────────────────────────────────────
   부서를 만든 기업이 얼마나 되고 계층이 몇 단계까지 가는지.
   (부서명은 수집하지 않으므로 이름 관련 점검은 없다.) */
SELECT
  COUNT(*)                                          AS departments,
  COUNT(DISTINCT company_seq)                       AS companies_with_department,
  COUNTIF(depth = 0)                                AS root_departments,
  MAX(depth)                                        AS max_depth,
  APPROX_QUANTILES(depth, 4)                        AS depth_quartiles
FROM `carbiz-6f7fc.cartax_statistics.raw_department`;


/* ── 16. purpose_code 가 무엇과 대응하나 ─────────────────────────────
   drivingLog.purpose 는 varchar(50) 코드다. purpose 테이블에 후보가 셋 있다.
     purposeCode varchar(20)  운행목적 코드
     purposeType varchar(20)  운행목적 타입
     purposeName varchar(20)  운행목적 이름
   어느 것과 붙는지 확인하기 전에는 이름으로 번역하지 않는다.

   ※ purpose 테이블에 companySeq 가 있다. 같은 코드가 기업마다 다른 뜻일 수
     있다는 뜻이다. 해석은 반드시 (company_seq, purpose_code) 쌍으로 한다.
     코드만으로 전사 집계하면 서로 다른 목적이 한 덩어리가 된다.

   purpose 테이블을 아직 반입하지 않아 지금은 분포만 본다. */
SELECT
  purpose_code,
  COUNT(*)                                          AS row_cnt,
  COUNT(DISTINCT company_seq)                       AS companies
FROM `carbiz-6f7fc.cartax_statistics.raw_trip`
WHERE trip_date >= '2016-01-01'
GROUP BY purpose_code ORDER BY row_cnt DESC LIMIT 40;
