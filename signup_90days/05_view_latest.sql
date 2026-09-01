CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_90days.view_signup_90days_latest` AS
/* =========================
   latest 대상: 회사별 최신 스냅샷 1행 + (히스토리 기반 파생변수)
   - 회사별 최신 스냅샷 1행(rn=1)
   - 회사별 최초 churn일(is_churned_date)을 별도 집계 후 JOIN
   - 선결제 / 유료전환 flag는 latest에서 생성 (alias 재참조 방지)
========================= */

WITH churn_by_company AS (
  /* =========================
     회사별 최초 churn 발생일
     - (한글) 히스토리 전체에서 회사별 첫 이탈 시점만 추출
  ========================= */
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

    /* =========================
       회사별 최초 churn일
       - (한글) 해당 회사가 과거에 이탈한 적이 있다면 최초 이탈일을 붙임
    ========================= */
    c.is_churned_date,

    /* =========================
       가입일부터 이탈까지 소요일
    ========================= */
    CASE
      WHEN c.is_churned_date IS NULL OR v.signup_date IS NULL THEN NULL
      ELSE DATE_DIFF(c.is_churned_date, v.signup_date, DAY)
    END AS days_to_churn,

    /* =========================
       가입 연도
       - signup_date 기준
    ========================= */
    EXTRACT(YEAR FROM v.signup_date) AS signup_year,

    /* =========================
       가입 월
       - signup_date 기준 (1~12)
    ========================= */
    EXTRACT(MONTH FROM v.signup_date) AS signup_month,

    /* =========================
       가입 연월
       - signup_date 기준 YYYY-MM
       - 월별 추이 분석용
    ========================= */
    FORMAT_DATE('%Y-%m', v.signup_date) AS signup_year_month,

    /* =========================
       첫 운행 전에 이탈했는지 (BOOL)
    ========================= */
    CASE
      WHEN c.is_churned_date IS NULL THEN NULL
      WHEN v.first_trip_date_start IS NULL THEN TRUE
      ELSE DATE(c.is_churned_date) < DATE(v.first_trip_date_start)
    END AS churn_before_activation,

    /* =========================
       첫 운행 전에 이탈했는지 (SUM용 FLAG: 0/1)
    ========================= */
    CASE
      WHEN c.is_churned_date IS NULL THEN 0
      WHEN v.first_trip_date_start IS NULL THEN 1
      WHEN DATE(c.is_churned_date) < DATE(v.first_trip_date_start) THEN 1
      ELSE 0
    END AS churn_before_activation_flag,

    /* is_paid_flag / plan_status는 view_signup_90days(04)에서 정의한 것을
       v.* 로 그대로 상속받는다. 여기서 다시 정의하지 않는다. */


    /* =========================
       최신 1행 선택용 rn
       - (한글) 회사별 가장 최근 스냅샷만 남기기 위함
    ========================= */
    ROW_NUMBER() OVER (
      PARTITION BY v.company_code
      ORDER BY v.snapshot_date DESC, v.data_collection_time DESC
    ) AS rn

  FROM `carbiz-6f7fc.signup_90days.view_signup_90days` v
  LEFT JOIN churn_by_company c
    ON c.company_code = v.company_code
),

final AS (
  SELECT
    base.*,

    /* =========================
       🔹 선결제 플래그
       - (한글) 예약일 존재 + trial 활성 상태이면 선결제로 판단
       - view_signup_90days에는 생성하지 않고 latest에서만 생성
    ========================= */
    IF(
      base.is_booking_date IS NOT NULL
      AND base.is_trial_active_flag = 1,
      1, 0
    ) AS is_pre_paid_flag,

    /* =========================
       🔹 탈퇴기업 플래그
       - (한글) user_count = 0 이면 탈퇴기업으로 판단
    ========================= */
    COALESCE(base.user_count = 0, FALSE) AS is_withdrawn_company

  FROM base
),

/* =========================
   회사별 최신 1행만 남긴 결과
   - (한글) 중복기업 판정은 히스토리 전체가 아니라
     "최신 스냅샷 1행" 기준으로 계산해야 하므로 여기서 먼저 필터링
========================= */
latest AS (
  SELECT *
  FROM final
  WHERE rn = 1
    AND company_code IS NOT NULL
),

/* =========================
   중복 기업 판정용 정규화 회사명
   - (한글) 대소문자/공백 차이로 인한 오탐 방지
========================= */
dedup AS (
  SELECT
    latest.*,
    LOWER(TRIM(latest.company_name)) AS company_name_norm
  FROM latest
),

dedup_flagged AS (
  SELECT
    dedup.*,

    /* 동일 회사명 계정 수 */
    COUNT(*) OVER (PARTITION BY dedup.company_name_norm) AS duplicate_company_count,

    /* 동일 회사명 중 유료 계정 수 */
    SUM(dedup.is_paid_flag) OVER (PARTITION BY dedup.company_name_norm) AS paid_account_count,

    /* 동일 회사명 중 유지 우선순위: 차량수 > 운행수 > 누적운행거리 > 사용자수 */
    ROW_NUMBER() OVER (
      PARTITION BY dedup.company_name_norm
      ORDER BY dedup.vehicle_count DESC, dedup.trip_count_total DESC, dedup.total_distance DESC, dedup.user_count DESC
    ) AS duplicate_keep_rank

  FROM dedup
)

/* =========================
   중복기업 최종 판정
   - (한글) 규칙
     1) 유료 계정 2개 이상 -> 전부 유지
     2) 유료 계정 정확히 1개 -> 그 유료 계정만 유지, 나머지(체험 등)는 제외
     3) 유료 계정 0개 -> 활동량 우선순위(duplicate_keep_rank) 1위만 유지
========================= */
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
