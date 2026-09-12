/* ============================================================================
   04. view_payment — 결제 사실 뷰
   ----------------------------------------------------------------------------
   결제 성공·실패·환불을 한 장으로 본다. 판정은 전부 여기서 한 번만 한다.
   아래 뷰들은 물려받기만 한다. (policy/10_naming.md — 같은 판정을 두 컬럼으로
   만들지 않는다)

   ★ fail_type — 설계안에서 「신호가 정반대」라고 쓴 부분
     갱신 실패는 이탈 위험이고, 라이선스를 늘리려다 실패한 것은 확장 의도다.
     섞이면 업셀 기회를 위험 고객으로 분류하게 된다.
     원천의 contractType 이 이미 둘을 구분해 준다. 날짜 대조로 추론할 필요가 없다.

   plan_level 은 1=free / 2=plus / 3=premium 이다 (2026-09-12 확인).
   이름 변환은 04_udf.sql 의 plan_name() 한 곳에만 둔다.
   ========================================================================= */

CREATE OR REPLACE VIEW `carbiz-6f7fc.cartax_statistics.view_payment` AS
WITH
/* 실제 결제 시도 — 성공·취소 */
attempt AS (
  SELECT
    p.payment_id,
    p.company_seq,
    p.contract_type,
    p.state,
    p.plan_level,
    p.license_count,
    p.term_month,
    p.contract_begin_date,
    p.contract_end_date,
    p.amount,
    p.total_amount,
    p.discount_amount,
    p.refund_amount,
    p.use_credit,
    p.return_credit,
    p.is_voucher,
    p.is_admin_created,
    p.created_at,
    p.updated_at,

    /* 결과 — 성공 / 취소 / 환불 */
    CASE
      WHEN p.state = 'Cancel'            THEN 'cancel'
      WHEN IFNULL(p.refund_amount, 0) > 0 THEN 'refund'
      WHEN p.state = 'Complete'          THEN 'success'
      ELSE 'pending'                     -- state = 'Apply'
    END AS result,

    /* 시도 성격 — 수동적 갱신인가, 능동적 확장인가 */
    CASE
      WHEN p.contract_type IN ('SCHEDULE','RENEW','RETRY','AGAIN') THEN 'renewal'
      WHEN p.contract_type IN ('UPGRADE','CHANGE','addCar','add')  THEN 'expansion'
      WHEN p.contract_type =  'OFFICIAL'                           THEN 'conversion'
      ELSE 'other'                                                 -- 'default' = 이관 이전 건
    END AS attempt_type,

    /* 순매출 — 환불을 뺀 실수령액 */
    IFNULL(p.amount, 0) - IFNULL(p.refund_amount, 0) AS net_amount
  FROM `carbiz-6f7fc.cartax_statistics.raw_payment` p
),

/* 정기결제 예약의 결과 — 실패가 여기에만 남는다 */
schedule AS (
  SELECT
    s.schedule_id,
    s.company_seq,
    s.product_type,
    s.plan_level,
    s.license_count,
    s.pay_cycle,
    s.pay_date,
    s.amount,
    s.status,
    s.error_message,
    s.created_at,
    s.updated_at,
    CASE s.status
      WHEN 'R' THEN 'reserved'
      WHEN 'Y' THEN 'success'
      WHEN 'C' THEN 'cancel'
      WHEN 'E' THEN 'fail'
    END AS result
  FROM `carbiz-6f7fc.cartax_statistics.raw_pay_schedule` s
)

/* 두 원천을 하나의 사실 흐름으로 합친다.
   payment  = 실제로 일어난 결제 건
   schedule = 예약과 그 결과. 실패(E)는 payment 에 행이 생기지 않는다 */
SELECT
  'payment'                   AS source,
  CAST(payment_id AS STRING)  AS event_id,
  company_seq,
  DATE(created_at)            AS event_date,
  attempt_type,
  result,
  contract_type               AS raw_type,
  plan_level,
  `carbiz-6f7fc.cartax_statistics`.plan_name(plan_level) AS plan_name,
  license_count,
  term_month,
  contract_begin_date,
  contract_end_date,
  amount,
  net_amount,
  refund_amount,
  CAST(NULL AS STRING)        AS pay_cycle,
  CAST(NULL AS STRING)        AS product_type,
  CAST(NULL AS STRING)        AS error_message,
  is_voucher,
  is_admin_created,
  created_at,
  updated_at
FROM attempt

UNION ALL

SELECT
  'schedule'                  AS source,
  CAST(schedule_id AS STRING) AS event_id,
  company_seq,
  DATE(pay_date)              AS event_date,
  'renewal'                   AS attempt_type,   -- 정기결제 예약은 전부 갱신 성격
  result,
  status                      AS raw_type,
  plan_level,
  `carbiz-6f7fc.cartax_statistics`.plan_name(plan_level) AS plan_name,
  license_count,
  CAST(NULL AS INT64)         AS term_month,
  CAST(NULL AS DATE)          AS contract_begin_date,
  CAST(NULL AS DATE)          AS contract_end_date,
  amount,
  IF(result = 'success', amount, 0) AS net_amount,
  CAST(NULL AS INT64)         AS refund_amount,
  pay_cycle,
  product_type,
  error_message,
  CAST(NULL AS BOOL)          AS is_voucher,
  CAST(NULL AS BOOL)          AS is_admin_created,
  created_at,
  updated_at
FROM schedule;
