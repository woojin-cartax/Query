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
            SELECT trip_id FROM `carbiz-6f7fc.source_db.raw_trip`
            WHERE trip_date >= '2016-01-01'))                AS orphan_child_rows,
  COUNTIF(overlap_state = 'REJECT')                          AS overlap_reject_rows,
  COUNTIF(overlap_state = 'OWN')                             AS overlap_own_rows,
  COUNT(*)                                                   AS total_rows
FROM `carbiz-6f7fc.source_db.raw_trip`
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
FROM `carbiz-6f7fc.source_db.raw_trip`
WHERE trip_date >= '2016-01-01'
GROUP BY yr ORDER BY yr;


/* ── 3. driving_type 실제 값 ──────────────────────────────────────────
   06번이 '수동' 이라는 문자열을 그대로 비교한다. 실제 값이 다르면 판정이 깨진다. */
SELECT driving_type, COUNT(*) AS row_cnt, COUNTIF(is_auto_start) AS auto_start_rows
FROM `carbiz-6f7fc.source_db.raw_trip`
WHERE trip_date >= '2016-01-01'
GROUP BY driving_type ORDER BY row_cnt DESC;


/* ── 4. plan_level 숫자 ↔ 요금제 이름 대응 ────────────────────────────
   아직 확인되지 않았다. 기존 signup_90days 의 FREE/PLUS/PREMIUM 과 맞춘다. */
SELECT c.plan_level, COUNT(*) AS companies,
       COUNTIF(s.is_trial_active) AS trial_companies,
       COUNTIF(s.pay_method = 'FREE') AS free_method_companies,
       APPROX_QUANTILES(s.license_count, 4) AS license_quartiles
FROM `carbiz-6f7fc.source_db.raw_company` c
LEFT JOIN `carbiz-6f7fc.source_db.raw_company_pay_state` s USING (company_seq)
GROUP BY c.plan_level ORDER BY c.plan_level;


/* ── 5. 사업자등록번호 확보율 ─────────────────────────────────────────
   언제부터 받기 시작했는지, 중복 판정을 얼마나 대체할 수 있는지 본다. */
SELECT
  EXTRACT(YEAR FROM signup_date)                             AS signup_year,
  COUNT(*)                                                   AS companies,
  COUNTIF(company_number IS NOT NULL AND company_number != '') AS has_number,
  ROUND(COUNTIF(company_number IS NOT NULL AND company_number != '')
        / COUNT(*) * 100, 1)                                 AS pct
FROM `carbiz-6f7fc.source_db.raw_company`
GROUP BY signup_year ORDER BY signup_year;


/* ── 6. 결제 실패 사유 — 자유 텍스트에 개인정보가 섞이는지 ────────────
   설계안 10-④. 실제 값을 보고 policy/30_data.md 를 채운다. */
SELECT error_message, COUNT(*) AS row_cnt
FROM `carbiz-6f7fc.source_db.raw_pay_schedule`
WHERE status = 'E' AND error_message IS NOT NULL
GROUP BY error_message ORDER BY row_cnt DESC LIMIT 50;


/* ── 7. createTime 이관 흔적 ─────────────────────────────────────────
   payment 샘플에서 seq 1~10 의 createTime 이 전부 2017-05-15 19:48:10 이었다.
   같은 값이 몇 건이나 뭉쳐 있는지 확인하고, 그 구간은 기간 분석에서 뺀다. */
SELECT DATE(created_at) AS created_date, COUNT(*) AS row_cnt,
       MIN(contract_begin_date) AS min_begin, MAX(contract_begin_date) AS max_begin
FROM `carbiz-6f7fc.source_db.raw_payment`
GROUP BY created_date ORDER BY row_cnt DESC LIMIT 10;
