CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_90days.view_signup_90days_monthly_base` AS
/* =========================
   monthly_base — 월별 리포트의 토대. 행 단위는 "월말 기준일 × 회사코드".

   월별 집계는 그 달 말일 스냅샷을 기준으로 한다. 08(요약)과 09(요금제별)가
   이 뷰를 읽으며, 두 표의 숫자가 서로 맞물리도록 판정을 여기서 한 번만 한다.

   중복기업 판정이 05 / 07과 다르다. 이유는 모집단이다.
     - 05는 "지금 시점 회사별 최신 1행", 07은 "그 스냅샷에 살아있는 행"만 본다.
     - 여기서는 **기준일까지의 모든 기록**에서 회사코드별 마지막 관측 행을 모은다.
       raw는 가입 후 90일까지만 새 행이 쌓이므로, 90일이 지난 계정은 07의 모집단에
       아예 없다. 그러면 같은 회사인데 일부만 보이는 상태로 중복을 판정하게 된다.
       기준일 이하 전체를 보면 그 계정도 판정에 들어온다.
     - "기준일까지"로 자르는 것이 중요하다. 자르지 않으면 미래 정보를 쓰게 되어
       같은 달 리포트를 나중에 다시 뽑을 때 숫자가 바뀐다.

   한계: 수집은 2026-01-26에 시작했고 가입 후 90일 이내만 담았다. 따라서
   2025-10-28 이전에 가입한 기업은 raw에 존재하지 않는다. 그 시절 유료 고객사가
   새 계정을 만들면 "유료 0개 그룹"으로 판정된다. 시간이 지나면 줄어드는 한계다.
========================= */

WITH ref AS (
  /* 각 달의 마지막 스냅샷 날짜. 진행 중인 달은 현재까지의 마지막 날이 된다. */
  SELECT
    FORMAT_DATE('%Y-%m', snapshot_date) AS ref_month,
    MAX(snapshot_date) AS ref_date
  FROM `carbiz-6f7fc.signup_90days.raw_signup_90days`
  GROUP BY ref_month
),

last_row AS (
  /* 기준일마다, 그 날짜 이하에서 회사코드별 마지막 관측 행 */
  SELECT * EXCEPT(rk)
  FROM (
    SELECT
      r.ref_month,
      r.ref_date,
      v.*,
      ROW_NUMBER() OVER (
        PARTITION BY r.ref_month, v.company_code
        ORDER BY v.snapshot_date DESC, v.data_collection_time DESC
      ) AS rk
    FROM ref r
    JOIN `carbiz-6f7fc.signup_90days.view_signup_90days` v
      ON v.snapshot_date <= r.ref_date
    WHERE v.company_code IS NOT NULL
  )
  WHERE rk = 1
),

flagged AS (
  SELECT
    l.*,

    /* 동일 회사명 계정 수 */
    COUNT(*) OVER (PARTITION BY l.ref_month, l.company_name_norm) AS duplicate_company_count,

    /* 동일 회사명 중 유료 계정 수 */
    SUM(l.is_paid_flag) OVER (PARTITION BY l.ref_month, l.company_name_norm) AS paid_account_count,

    /* 실사용 중인 무료·체험 계정인가.
       최근 2주 운행이 14회 이상, 즉 하루 최소 1회. 유료 계정과 같은 이름으로 묶였더라도
       실제로 쓰고 있으면 별개 기업으로 인정하기 위한 조건이다.
       (2026-09-02 기준으로는 한 번도 발동하지 않는다. 앞으로를 위한 안전망이다.) */
    IF(l.is_paid_flag = 0 AND l.trip_count_recent_2w >= 14, 1, 0) AS is_active_free,

    /* 유지 우선순위: 차량수 > 누적 운행수 > 누적 운행거리 > 사용자수.
       마지막 company_code는 동점 시 결정적 tiebreak다. 없으면 순위가 실행마다 달라진다. */
    ROW_NUMBER() OVER (
      PARTITION BY l.ref_month, l.company_name_norm
      ORDER BY l.vehicle_count DESC, l.trip_count_total DESC, l.total_distance DESC, l.user_count DESC,
               l.company_code
    ) AS duplicate_keep_rank

  FROM last_row l
),

judged AS (
  SELECT
    f.*,

    f.company_name_norm IS NOT NULL AND f.duplicate_company_count > 1 AS is_duplicate_company,

    /* 중복기업 판정
         1) 유료 2개 이상                  -> 그룹 전체 유지
         2) 유료 1개                       -> 유료 계정 + 실사용 중인 무료·체험 계정만 유지
         3) 유료 0개                       -> 활동량 1위만 유지 */
    CASE
      WHEN f.manual_override = 'exclude' THEN TRUE
      WHEN f.manual_override = 'keep'    THEN FALSE
      WHEN f.paid_account_count >= 2 THEN FALSE
      WHEN f.paid_account_count = 1 THEN NOT (f.is_paid_flag = 1 OR f.is_active_free = 1)
      ELSE f.duplicate_keep_rank > 1
    END AS duplicate_exclude_flag

  FROM flagged f
)

SELECT
  j.* EXCEPT(duplicate_exclude_flag),
  j.duplicate_exclude_flag,

  /* 집계 대상 여부와 제외 사유. 제외된 기업 목록은 exclude_reason으로 뽑는다.
     사유가 겹칠 때는 우선순위대로 하나만 남긴다.
       test > withdrawn > manual > duplicate
     manual은 사람이 00_manual_override.sql에 직접 적어 뺀 경우다.
     수동 test 지정은 is_test_account에 이미 반영돼 test로 찍힌다. */
  CASE
    WHEN j.is_test_account THEN 'test'
    WHEN j.is_withdrawn_company THEN 'withdrawn'
    WHEN j.manual_override = 'exclude' THEN 'manual'
    WHEN j.duplicate_exclude_flag THEN 'duplicate'
    ELSE NULL
  END AS exclude_reason,

  NOT (j.is_test_account OR j.is_withdrawn_company OR j.duplicate_exclude_flag) AS is_counted

FROM judged j;
