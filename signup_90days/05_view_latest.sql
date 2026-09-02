CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_90days.view_signup_90days_latest` AS
/* =========================
   latest — 회사별 최신 스냅샷 1행 + 중복기업 판정

   파생컬럼(이탈일·소요일·가입연월·선결제·탈퇴·유료판정·rn)은 전부
   view_signup_90days(04)에서 만들어 상속받는다. 여기서 다시 정의하지 않는다.
   이 파일이 하는 일은 "회사별 최신 1행으로 좁힌 뒤의 중복기업 판정"뿐이다.

   07_view_by_snapshot_date.sql과의 차이는 딱 두 곳이다.
     1) 행 범위         : 여기는 rn = 1,          07은 필터 없음
     2) dedup PARTITION : 여기는 company_name_norm,
                          07은 snapshot_date + company_name_norm
   그 외는 동일하게 유지한다. 한쪽만 고치지 않는다.
========================= */

WITH latest AS (
  /* 회사별 최신 스냅샷 1행.
     중복기업 판정은 히스토리 전체가 아니라 최신 1행 기준으로 계산해야 하므로
     여기서 먼저 좁힌다. */
  SELECT *
  FROM `carbiz-6f7fc.signup_90days.view_signup_90days`
  WHERE rn = 1
    AND company_code IS NOT NULL
),

dedup AS (
  /* company_name_norm은 view_signup_90days(04)에서 만든 것을 상속받는다.
     여기서 다시 정의하지 않는다. 05 / 07 / 06_monthly_base가 같은 기준을 써야 한다. */
  SELECT latest.*
  FROM latest
),

dedup_flagged AS (
  SELECT
    dedup.*,

    /* 동일 회사명 계정 수 */
    COUNT(*) OVER (PARTITION BY dedup.company_name_norm) AS duplicate_company_count,

    /* 동일 회사명 중 유료 계정 수 */
    SUM(dedup.is_paid_flag) OVER (PARTITION BY dedup.company_name_norm) AS paid_account_count,

    /* 동일 회사명 중 유지 우선순위: 차량수 > 운행수 > 누적운행거리 > 사용자수
       마지막 company_code는 동점 시 결정적 tiebreak다. 활동량이 전부 0인 빈 계정끼리
       같은 회사명으로 묶이면 정렬키 4개가 모두 동점이 되어 ROW_NUMBER의 순위가
       실행마다 달라진다. 실제로 같은 그룹에서 세 번 실행에 세 번 다른 계정이
       살아남는 것을 확인했다. 어느 계정이 남느냐는 임의지만 항상 같아야 한다. */
    ROW_NUMBER() OVER (
      PARTITION BY dedup.company_name_norm
      ORDER BY dedup.vehicle_count DESC, dedup.trip_count_total DESC, dedup.total_distance DESC, dedup.user_count DESC,
               dedup.company_code
    ) AS duplicate_keep_rank

  FROM dedup
)

/* =========================
   중복기업 최종 판정
     1) 유료 계정 2개 이상  -> 전부 유지
     2) 유료 계정 정확히 1개 -> 그 유료 계정만 유지, 나머지(체험 등)는 제외
     3) 유료 계정 0개       -> 활동량 우선순위(duplicate_keep_rank) 1위만 유지
========================= */
SELECT
  dedup_flagged.*,

  dedup_flagged.company_name_norm IS NOT NULL AND duplicate_company_count > 1 AS is_duplicate_company,

  CASE
    WHEN paid_account_count >= 2 THEN TRUE
    WHEN paid_account_count = 1 THEN dedup_flagged.is_paid_flag = 1
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
    WHEN paid_account_count = 1 THEN dedup_flagged.is_paid_flag = 0
    ELSE dedup_flagged.duplicate_keep_rank > 1
  END AS duplicate_exclude_flag

FROM dedup_flagged;
