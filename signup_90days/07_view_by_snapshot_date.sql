CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_90days.view_signup_90days_by_snapshot` AS
/* =========================
   by_snapshot 대상: 05_view_latest.sql과 동일한 파생 구성이나,
   "회사별 최신 1행"으로 좁히지 않고 스냅샷 날짜별 전체 행을 유지함.
   - 특정 snapshot_date 하나를 골라 WHERE 걸면 "그 시점"의 전체 현황을 볼 수 있음
   - 중복기업 판정(company_name_norm 기준)은 스냅샷 날짜 단위로 다시 계산함
     (날짜를 파티션에 넣지 않으면 같은 회사의 서로 다른 날짜 스냅샷끼리
      "중복"으로 잘못 묶임)
========================= */

WITH churn_by_company AS (
  SELECT
    company_code,
    MIN(snapshot_date) AS is_churned_date
  FROM `carbiz-6f7fc.signup_90days.view_signup_90days`
  WHERE company_code IS NOT NULL
    AND is_churned IS TRUE
  GROUP BY company_code
),

base AS (
  SELECT
    v.*,

    c.is_churned_date,

    CASE
      WHEN c.is_churned_date IS NULL OR v.signup_date IS NULL THEN NULL
      ELSE DATE_DIFF(c.is_churned_date, v.signup_date, DAY)
    END AS days_to_churn,

    EXTRACT(YEAR FROM v.signup_date) AS signup_year,
    EXTRACT(MONTH FROM v.signup_date) AS signup_month,
    FORMAT_DATE('%Y-%m', v.signup_date) AS signup_year_month,

    CASE
      WHEN c.is_churned_date IS NULL THEN NULL
      WHEN v.first_trip_date_start IS NULL THEN TRUE
      ELSE DATE(c.is_churned_date) < DATE(v.first_trip_date_start)
    END AS churn_before_activation,

    CASE
      WHEN c.is_churned_date IS NULL THEN 0
      WHEN v.first_trip_date_start IS NULL THEN 1
      WHEN DATE(c.is_churned_date) < DATE(v.first_trip_date_start) THEN 1
      ELSE 0
    END AS churn_before_activation_flag,

    /* is_paid_flag / plan_status는 view_signup_90days(04)에서 정의한 것을
       v.* 로 그대로 상속받는다. 여기서 다시 정의하지 않는다. */

    /* 참고용: 회사별 최신 스냅샷 여부(1=최신). 05번 view_latest의 rn과 동일 정의 */
    ROW_NUMBER() OVER (
      PARTITION BY v.company_code
      ORDER BY v.snapshot_date DESC, v.data_collection_time DESC
    ) AS rn

  FROM `carbiz-6f7fc.signup_90days.view_signup_90days` v
  LEFT JOIN churn_by_company c
    ON c.company_code = v.company_code
),

with_flags AS (
  SELECT
    base.*,

    IF(
      base.is_booking_date IS NOT NULL
      AND base.is_trial_active_flag = 1,
      1, 0
    ) AS is_pre_paid_flag,

    COALESCE(base.user_count = 0, FALSE) AS is_withdrawn_company

  FROM base
),

snapshot_rows AS (
  /* 05번의 "latest"와 달리 rn=1 필터를 걸지 않음 -> 모든 snapshot_date 유지 */
  SELECT *
  FROM with_flags
  WHERE company_code IS NOT NULL
),

dedup AS (
  SELECT
    snapshot_rows.*,
    LOWER(TRIM(snapshot_rows.company_name)) AS company_name_norm
  FROM snapshot_rows
),

dedup_flagged AS (
  SELECT
    dedup.*,

    COUNT(*) OVER (
      PARTITION BY dedup.snapshot_date, dedup.company_name_norm
    ) AS duplicate_company_count,

    SUM(dedup.is_paid_flag) OVER (
      PARTITION BY dedup.snapshot_date, dedup.company_name_norm
    ) AS paid_account_count,

    /* 정렬키 동점 시 company_code로 결정적 tiebreak. 근거는 05_view_latest.sql 참조 */
    ROW_NUMBER() OVER (
      PARTITION BY dedup.snapshot_date, dedup.company_name_norm
      ORDER BY dedup.vehicle_count DESC, dedup.trip_count_total DESC, dedup.total_distance DESC, dedup.user_count DESC,
               dedup.company_code
    ) AS duplicate_keep_rank

  FROM dedup
)

SELECT
  dedup_flagged.*,

  dedup_flagged.company_name_norm IS NOT NULL AND duplicate_company_count > 1 AS is_duplicate_company,

  CASE
    WHEN paid_account_count >= 2 THEN TRUE
    WHEN paid_account_count = 1 THEN dedup_flagged.is_paid_flag = 1
    ELSE dedup_flagged.duplicate_keep_rank = 1
  END AS duplicate_keep_flag,

  CASE
    WHEN paid_account_count >= 2 THEN FALSE
    WHEN paid_account_count = 1 THEN dedup_flagged.is_paid_flag = 0
    ELSE dedup_flagged.duplicate_keep_rank > 1
  END AS duplicate_exclude_flag

FROM dedup_flagged;
