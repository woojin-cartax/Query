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


/* ── 8. 탈퇴 판정 — 세 상태의 활동 차이 ──────────────────────────────
   90일 스냅샷에서는 탈퇴 컬럼이 없어 user_count = 0 을 대리지표로 썼다.
   이제 company.enabled 에 X(탈퇴)가 명시돼 있다. 대리지표가 필요 없다.

   Y 사용가능 / N 미사용 / X 탈퇴, 셋이다. X 와 N 을 묶지 않는다.
   판정은 확정됐고, 여기서는 셋의 활동 흔적이 실제로 어떻게 다른지만 본다.
   N 과 X 의 활동 패턴이 구분되지 않으면 그때 다시 본다. */
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
   role_seq = 0 이 최고관리자이고 나머지는 전부 사용자다 (2026-09-12 확인).
   확정된 규칙이므로 이건 검증이지 탐색이 아니다. 두 가지로 본다.

   ① role_seq = 0 인 사용자가 비즈 관리자 페이지에 로그인하는가
      권한이 맞다면 has_admin_login 비율이 0 그룹에서 압도적으로 높아야 한다.
   ② role_seq = 0 이 아닌데 관리자 콘솔에 들어오는 사용자가 있는가
      확정된 규칙과 어긋나면 데이터에 이상이 있는 것이다. 규칙을 고치기 전에
      왜 그런지부터 본다.

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


/* ── 16. purpose_code 의 조인 키 확정 ────────────────────────────────
   drivingLog.purpose 가 purpose 테이블의 무엇과 붙는지 세 후보의 매칭률을 잰다.
   가장 높은 것이 조인 키다. 07_view_trip.sql 의 ON 절을 그것으로 확정한다.

   ※ 매칭은 반드시 company_seq 를 함께 건다. 운행목적은 기업별 정의라
     코드만으로 맞추면 A사 코드에 B사 이름이 붙는다. 그건 NULL 로도 안 드러나고
     그럴듯한 값이 나와서 더 위험하다. 아래 by_code_only 가 그 위험의 크기다 —
     with_company 와 차이가 크면 코드가 기업 간에 실제로 겹치고 있다는 뜻이다. */
WITH t AS (
  SELECT company_seq, purpose_code, COUNT(*) AS row_cnt
  FROM `carbiz-6f7fc.cartax_statistics.raw_trip`
  WHERE trip_date >= '2016-01-01' AND purpose_code IS NOT NULL
  GROUP BY company_seq, purpose_code
)
SELECT
  SUM(t.row_cnt)                                    AS total_rows,
  SUM(IF(EXISTS(SELECT 1 FROM `carbiz-6f7fc.cartax_statistics.raw_purpose` p
         WHERE p.company_seq = t.company_seq AND p.purpose_code = t.purpose_code),
         t.row_cnt, 0))                             AS match_by_code,
  SUM(IF(EXISTS(SELECT 1 FROM `carbiz-6f7fc.cartax_statistics.raw_purpose` p
         WHERE p.company_seq = t.company_seq AND p.purpose_type = t.purpose_code),
         t.row_cnt, 0))                             AS match_by_type,
  SUM(IF(EXISTS(SELECT 1 FROM `carbiz-6f7fc.cartax_statistics.raw_purpose` p
         WHERE p.company_seq = t.company_seq AND p.purpose_name = t.purpose_code),
         t.row_cnt, 0))                             AS match_by_name,
  SUM(IF(EXISTS(SELECT 1 FROM `carbiz-6f7fc.cartax_statistics.raw_purpose` p
         WHERE p.purpose_code = t.purpose_code),
         t.row_cnt, 0))                             AS match_by_code_only
FROM t;


/* ── 16b. 같은 코드가 기업마다 다른 뜻인가 ───────────────────────────
   한 코드에 이름이 둘 이상 붙어 있으면, 코드만으로 전사 집계할 수 없다.
   그 개수가 크면 대시보드에서 운행목적을 전사 비교하는 것 자체가 무의미하다. */
SELECT
  purpose_code,
  COUNT(DISTINCT purpose_name)                      AS distinct_names,
  COUNT(DISTINCT company_seq)                       AS companies,
  ARRAY_AGG(DISTINCT purpose_name IGNORE NULLS LIMIT 8) AS sample_names
FROM `carbiz-6f7fc.cartax_statistics.raw_purpose`
GROUP BY purpose_code
HAVING COUNT(DISTINCT purpose_name) > 1
ORDER BY distinct_names DESC LIMIT 30;


/* ── 16c. 운행에 쓰인 코드 분포 ─────────────────────────────────────── */
SELECT
  purpose_code,
  COUNT(*)                                          AS row_cnt,
  COUNT(DISTINCT company_seq)                       AS companies
FROM `carbiz-6f7fc.cartax_statistics.raw_trip`
WHERE trip_date >= '2016-01-01'
GROUP BY purpose_code ORDER BY row_cnt DESC LIMIT 40;


/* ── 17. 도입 단계 분포 ──────────────────────────────────────────────
   우리 제품의 행동은 두 단계다. 1단계는 고객사와 최고관리자, 2단계는 관리자가
   사용자에게 확산하는 것이다. 어디서 막히는지 먼저 본다.

   ★ 2단계로 못 넘어간 기업의 비율이 이 파이프라인의 첫 번째 답이다.
     관리자 혼자 쓰다 끝나는 기업이 많으면 제품 문제가 아니라 온보딩 문제다.

   ※ 1인 계약을 반드시 갈라서 본다. 확산할 대상이 없는 기업을 「막힌 기업」으로
     세면 전환율이 실제보다 나쁘게 나온다. */
SELECT
  is_single_seat,
  stage,
  stage_label,
  COUNT(*)                                          AS companies,
  COUNTIF(NOT is_withdrawn)                         AS alive,
  COUNTIF(first_payment_date IS NOT NULL)           AS ever_paid,
  ROUND(AVG(days_since_last_milestone), 0)          AS avg_days_stuck,
  ROUND(AVG(license_count), 1)                      AS avg_license
FROM `carbiz-6f7fc.cartax_statistics.view_company_stage`
WHERE NOT is_test_account
GROUP BY is_single_seat, stage, stage_label
ORDER BY is_single_seat, stage;


/* ── 18. 확산이 갱신과 상관이 있나 ───────────────────────────────────
   가설: 관리자 혼자 쓰는 기업과 직원까지 퍼진 기업은 갱신 확률이 다르다.
   이게 사실이면 확산 지표가 건강 상태의 1순위가 되고, 아니면 다른 축을 찾아야 한다.

   ※ 상관이지 인과가 아니다. 원래 규모가 큰 기업이 확산도 잘 되고 갱신도 잘 하는
     것일 수 있다. license_count 를 같이 봐서 규모 효과를 가늠한다.

   ※ 1인 계약은 확산이 불가능하므로 has_expanded=FALSE 에 무조건 들어간다.
     갈라 보지 않으면 「확산 안 한 기업도 잘 갱신한다」는 잘못된 결론이 나온다. */
SELECT
  is_single_seat,
  has_expanded,
  COUNT(*)                                          AS companies,
  COUNTIF(is_withdrawn)                             AS withdrawn,
  ROUND(COUNTIF(is_withdrawn) / COUNT(*) * 100, 1)  AS withdrawn_pct,
  COUNTIF(is_auto_pay)                              AS auto_pay_on,
  COUNTIF(first_payment_date IS NOT NULL)           AS ever_paid,
  ROUND(AVG(license_count), 1)                      AS avg_license,
  ROUND(AVG(member_activation_rate) * 100, 1)       AS avg_member_activation_pct
FROM `carbiz-6f7fc.cartax_statistics.view_company_stage`
WHERE NOT is_test_account
GROUP BY is_single_seat, has_expanded
ORDER BY is_single_seat, has_expanded;


/* ── 19. 아하 모먼트 후보 비교 ───────────────────────────────────────
   후보가 둘이고 배타적이지 않다. 둘 다 재고 어느 쪽이 갱신·이탈과 더 붙는지 본다.

     ① 회사의 첫 N건 운행 — 누가 기록했는지 상관없다. 현재 가설은 5건
     ② 관리자가 아닌 첫 직원의 운행 — 확산이 일어난 시점

   유지 기업의 중앙값이 이탈 기업보다 뚜렷하게 짧으면 그 지표가 후보다.
   차이가 안 나면 다른 후보를 찾는다. 확정이 아니라 탐색이다. */
SELECT
  IF(is_withdrawn, '이탈', '유지')                   AS status,
  COUNT(*)                                          AS companies,
  -- ① 회사 기준 도달 속도
  COUNTIF(reached_aha)                              AS reached_trip_5,
  ROUND(COUNTIF(reached_aha) / COUNT(*) * 100, 1)   AS reached_trip_5_pct,
  APPROX_QUANTILES(days_to_trip_1, 4)               AS days_to_trip_1_q,
  APPROX_QUANTILES(days_to_trip_3, 4)               AS days_to_trip_3_q,
  APPROX_QUANTILES(days_to_trip_5, 4)               AS days_to_trip_5_q,
  APPROX_QUANTILES(days_to_trip_10, 4)              AS days_to_trip_10_q,
  -- ② 확산
  APPROX_QUANTILES(days_to_member_trip, 4)          AS days_to_member_trip_q,
  APPROX_QUANTILES(days_admin_to_member_trip, 4)    AS days_admin_to_member_q,
  COUNTIF(invited_but_no_trip)                      AS invited_but_no_trip,
  COUNTIF(expansion_stalled)                        AS expansion_stalled
FROM `carbiz-6f7fc.cartax_statistics.view_company_stage`
WHERE NOT is_test_account
  AND NOT is_single_seat          -- 확산 후보(②)를 재려면 확산 가능한 기업만 본다
GROUP BY status;


/* ── 19b. N을 몇으로 잡아야 하나 ─────────────────────────────────────
   「첫 5건」은 가설이다. 1·3·5·10 중 유지/이탈을 가장 크게 가르는 것이 답이다.
   도달률 차이(유지 − 이탈)가 가장 큰 N을 고른다.

   ※ 생존 편향에 주의한다. 오래 산 기업이 당연히 더 많은 운행을 쌓는다.
     가입 후 30일 안에 도달했는가로 잘라서 기간을 맞춘다. */
SELECT n,
  COUNTIF(NOT withdrawn)                            AS alive,
  COUNTIF(withdrawn)                                AS churned,
  ROUND(COUNTIF(NOT withdrawn AND within_30d) / NULLIF(COUNTIF(NOT withdrawn), 0) * 100, 1)
                                                    AS alive_reached_pct,
  ROUND(COUNTIF(withdrawn AND within_30d) / NULLIF(COUNTIF(withdrawn), 0) * 100, 1)
                                                    AS churned_reached_pct
FROM (
  SELECT is_withdrawn AS withdrawn, n, d <= 30 AS within_30d
  FROM `carbiz-6f7fc.cartax_statistics.view_company_stage`,
  UNNEST([STRUCT(1 AS n, days_to_trip_1 AS d),
          (3, days_to_trip_3), (5, days_to_trip_5), (10, days_to_trip_10)])
  WHERE NOT is_test_account
)
GROUP BY n ORDER BY n;


/* ── 20. 확산이 먼저인가 결제가 먼저인가 ─────────────────────────────
   확산이 결제를 부르는지, 결제하고 나서 확산하는지. 순서가 개입 시점을 정한다.
   확산이 먼저라면 무료 구간의 온보딩에 투자해야 하고,
   결제가 먼저라면 결제 직후가 확산 개입의 골든타임이다. */
SELECT
  expanded_before_payment,
  COUNT(*)                                          AS companies,
  COUNTIF(is_withdrawn)                             AS withdrawn,
  ROUND(AVG(days_to_first_payment), 0)              AS avg_days_to_payment,
  ROUND(AVG(days_to_member_trip), 0)                AS avg_days_to_member_trip
FROM `carbiz-6f7fc.cartax_statistics.view_company_stage`
WHERE NOT is_test_account AND first_payment_date IS NOT NULL
GROUP BY expanded_before_payment;


/* ── 21. 1인 계약의 규모 ─────────────────────────────────────────────
   우리 고객사에는 혼자 쓰는 기업이 있다. 그 경우 관리자가 곧 사용자이고,
   확산할 대상이 구조적으로 없다. 이들을 「2단계에서 막힌 기업」으로 세면
   전환율과 확산-갱신 상관이 둘 다 왜곡된다.

   판정 기준을 데이터로 정하려고 두 축을 교차한다.
     라이선스 수  계약상 몇 자리를 샀나
     사용자 수    실제로 몇 명이 있나

   ★ license_count 가 NULL 인 기업(무료·체험으로 보인다)의 규모를 먼저 본다.
     현재 is_single_seat 은 NULL 을 FALSE 로 떨어뜨린다. 그 수가 크면 판정을 다시 짠다. */
SELECT
  CASE
    WHEN license_count IS NULL THEN 'NULL'
    WHEN license_count <= 1    THEN '1'
    WHEN license_count <= 3    THEN '2-3'
    WHEN license_count <= 10   THEN '4-10'
    ELSE '11+'
  END                                               AS license_bucket,
  CASE
    WHEN user_count_total = 0 THEN '0'
    WHEN user_count_total = 1 THEN '1'
    WHEN user_count_total <= 3 THEN '2-3'
    ELSE '4+'
  END                                               AS user_bucket,
  COUNT(*)                                          AS companies,
  COUNTIF(is_withdrawn)                             AS withdrawn,
  COUNTIF(has_expanded)                             AS expanded,
  COUNTIF(first_payment_date IS NOT NULL)           AS ever_paid,
  ROUND(AVG(admin_trip_count), 0)                   AS avg_admin_trips,
  ROUND(AVG(member_trip_count), 0)                  AS avg_member_trips
FROM `carbiz-6f7fc.cartax_statistics.view_company_stage`
WHERE NOT is_test_account
GROUP BY license_bucket, user_bucket
ORDER BY license_bucket, user_bucket;


/* ── 21b. 1인 계약이 정말 다른가 ─────────────────────────────────────
   가른 것이 의미가 있는지 확인한다. 1인 계약의 이탈률이 여러 자리 계약과
   비슷하다면 굳이 나눌 이유가 없다. 다르다면 별도 세그먼트로 본다.

   ※ 자리를 여러 개 샀는데 관리자 혼자 쓰는 기업(expansion_stalled)이 진짜 개입
     대상이다. 1인 계약과 섞이면 그 신호가 묻힌다. */
SELECT
  CASE
    WHEN is_single_seat     THEN '1인 계약'
    WHEN expansion_stalled  THEN '여러 자리인데 관리자 혼자'
    WHEN has_expanded       THEN '확산됨'
    ELSE '기타'
  END                                               AS segment,
  COUNT(*)                                          AS companies,
  COUNTIF(is_withdrawn)                             AS withdrawn,
  ROUND(COUNTIF(is_withdrawn) / COUNT(*) * 100, 1)  AS withdrawn_pct,
  COUNTIF(is_auto_pay)                              AS auto_pay_on,
  ROUND(AVG(license_count), 1)                      AS avg_license,
  ROUND(AVG(license_fill_rate) * 100, 1)            AS avg_fill_pct
FROM `carbiz-6f7fc.cartax_statistics.view_company_stage`
WHERE NOT is_test_account
GROUP BY segment ORDER BY companies DESC;
