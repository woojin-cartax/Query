CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_90days.view_signup_90days_by_snapshot` AS
/* =========================
   by_snapshot — 스냅샷 날짜별 전체 행 + 그 날짜 기준 중복기업 판정

   특정 snapshot_date 하나를 골라 WHERE를 걸면 "그 시점"의 전체 현황을 볼 수 있다.
   04(view_signup_90days)만으로는 이걸 못 한다. 04에는 중복기업 판정이 없어서
   같은 회사의 계정이 여러 개면 전부 세어지기 때문이다.

   05(latest)를 rn = 1로 필터해도 이 뷰가 나오지 않는다. 판정 범위가 다르다.
     - 05: 회사마다 자기 최신 스냅샷 1행씩 모아 그것들끼리 비교한다.
           최신 날짜가 서로 달라도 비교 대상이 된다.
     - 07: 같은 snapshot_date 안에서만 비교한다. 그 날짜에 없는 회사는 대상이 아니다.

   05_view_latest.sql과의 차이는 딱 두 곳이다.
     1) 행 범위         : 여기는 필터 없음,      05는 rn = 1
     2) dedup PARTITION : 여기는 snapshot_date + company_name_norm,
                          05는 company_name_norm
   그 외는 동일하게 유지한다. 한쪽만 고치지 않는다.

   파생컬럼은 전부 04에서 만들어 상속받는다. 여기서 다시 정의하지 않는다.

   [주의] 2026-07-29 스냅샷은 소급 적재분이라 당시 상태가 아니다.
   원본이 2026-09-02에 재생성됐고, 수집 원본은 가입 후 90일 이내 기업만 담으므로
   재생성 시점에 이미 90일이 지난 기업은 빠져 있다. 672행으로 인접일보다 70여 건 적다.
   그날의 전체 현황으로 읽으면 안 된다.
========================= */

WITH snapshot_rows AS (
  /* 05의 latest와 달리 rn = 1 필터를 걸지 않는다 -> 모든 snapshot_date 유지 */
  SELECT *
  FROM `carbiz-6f7fc.signup_90days.view_signup_90days`
  WHERE company_code IS NOT NULL
),

dedup AS (
  /* company_name_norm은 view_signup_90days(04)에서 만든 것을 상속받는다.
     여기서 다시 정의하지 않는다. 05 / 07 / 06_monthly_base가 같은 기준을 써야 한다. */
  SELECT snapshot_rows.*
  FROM snapshot_rows
),

dedup_flagged AS (
  SELECT
    dedup.*,

    /* 아래 세 윈도우는 전부 snapshot_date를 PARTITION에 포함한다.
       날짜를 빼면 같은 회사의 서로 다른 날짜 스냅샷끼리 "중복"으로 잘못 묶인다. */
    COUNT(*) OVER (
      PARTITION BY dedup.snapshot_date, dedup.company_name_norm
    ) AS duplicate_company_count,

    SUM(dedup.is_paid_flag) OVER (
      PARTITION BY dedup.snapshot_date, dedup.company_name_norm
    ) AS paid_account_count,


    /* 실사용 중인 무료·체험 계정인가.
       최근 2주 운행이 14회 이상, 즉 하루 최소 1회. 유료 계정과 같은 이름으로 묶였더라도
       실제로 쓰고 있으면 별개 기업으로 인정한다.
       06_monthly_base와 같은 기준이다. 두 뷰의 중복 규칙은 반드시 같아야 한다. */
    IF(dedup.is_paid_flag = 0 AND dedup.trip_count_recent_2w >= 14, 1, 0) AS is_active_free,

    /* 정렬키 동점 시 company_code로 결정적 tiebreak. 근거는 05_view_latest.sql 참조 */
    ROW_NUMBER() OVER (
      PARTITION BY dedup.snapshot_date, dedup.company_name_norm
      ORDER BY dedup.vehicle_count DESC, dedup.trip_count_total DESC, dedup.total_distance DESC, dedup.user_count DESC,
               dedup.company_code
    ) AS duplicate_keep_rank

  FROM dedup
)

/* =========================
   중복기업 최종 판정 — 05와 동일한 규칙
     1) 유료 계정 2개 이상  -> 전부 유지
     2) 유료 계정 정확히 1개 -> 유료 계정 + 실사용 중인 무료·체험 계정을 유지
                               (is_active_free: 최근 2주 운행 14회 이상)
     3) 유료 계정 0개       -> 활동량 우선순위 1위만 유지
========================= */
SELECT
  dedup_flagged.*,

  dedup_flagged.company_name_norm IS NOT NULL AND duplicate_company_count > 1 AS is_duplicate_company,

  CASE
    WHEN paid_account_count >= 2 THEN TRUE
    WHEN paid_account_count = 1 THEN (dedup_flagged.is_paid_flag = 1 OR dedup_flagged.is_active_free = 1)
    ELSE dedup_flagged.duplicate_keep_rank = 1
  END AS duplicate_keep_flag,

  /* 자동 중복 판정 위에 수동 판정을 얹는다.
       manual_override = 'exclude' -> 무조건 제외
       manual_override = 'keep'    -> 중복 제외를 되살림
     규칙과 우선순위는 00_manual_override.sql 참조. */
  CASE
    WHEN dedup_flagged.manual_override = 'exclude' THEN TRUE
    WHEN dedup_flagged.manual_override = 'keep'    THEN FALSE
    WHEN paid_account_count >= 2 THEN FALSE
    WHEN paid_account_count = 1 THEN NOT (dedup_flagged.is_paid_flag = 1 OR dedup_flagged.is_active_free = 1)
    ELSE dedup_flagged.duplicate_keep_rank > 1
  END AS duplicate_exclude_flag

FROM dedup_flagged;
