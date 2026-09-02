CREATE OR REPLACE VIEW `carbiz-6f7fc.signup_90days.view_signup_90days` AS

WITH base AS (
  SELECT
    r.*,

    /* 소스 추출 */
    CASE
      WHEN r.signup_device IS NULL OR TRIM(r.signup_device) = '' THEN NULL
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'구글') THEN 'google'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'네이버_블로그') THEN 'naverblog'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'네이버웍스') THEN 'naverworks'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'네이버') THEN 'naver'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'카카오웰') THEN 'kakaowelcome'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'카카오') THEN 'kakao'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'다우오피스') THEN 'dowoffice'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'kt비즈오피스') THEN 'ktbizoffice'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'뉴스와이어') THEN 'newswire'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'깃북') THEN 'gitbook'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'나무위키') THEN 'namuwiki'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'유튜브') THEN 'youtube'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'페이스북') THEN 'facebook'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'chatgpt') THEN 'chatgpt'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'perplexity') THEN 'perplexity'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'ppss') THEN 'ppss'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'teams') THEN 'teams'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'빙') THEN 'bing'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'네이트') THEN 'nate'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'스티비') THEN 'stibe'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'티스토리') THEN 'tistory'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'aos') THEN 'android'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'ios') THEN 'ios'
      WHEN LOWER(TRIM(r.signup_device)) = 'direct' THEN 'direct'
      ELSE 'not_set'
    END AS signup_source,

    /* 채널 추출 */
    CASE
      WHEN r.signup_device IS NULL OR TRIM(r.signup_device) = '' THEN NULL
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'자연검색') THEN 'organic'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'cpc') THEN 'cpc'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'aos|ios|웍스|블로그') THEN 'referral'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'페이스북|인스타|social') THEN 'social'
      WHEN REGEXP_CONTAINS(LOWER(r.signup_device), r'referral') THEN 'referral'
      WHEN LOWER(TRIM(r.signup_device)) = 'direct' THEN 'direct'
      ELSE 'not_set'
    END AS signup_channel,

    /* 키워드 추출 */
    CASE
      WHEN r.signup_device IS NULL OR TRIM(r.signup_device) = '' THEN NULL
      ELSE NULLIF(
        REGEXP_EXTRACT(r.signup_device, r'^[^_]+_[^_]+_[(]?([^\)_]+)[)]?$'),
        ''
      )
    END AS signup_keyword,

    /* 가입 디바이스 */
    CASE
      WHEN r.signup_device IS NULL OR TRIM(r.signup_device) = '' THEN '알수없음'
      WHEN REGEXP_CONTAINS(r.signup_device, r'앱') THEN 'app'
      ELSE 'pc'
    END AS signup_device_refine,

    /* 결제 수단 */
    CASE
      WHEN r.contract_type IS NULL OR TRIM(r.contract_type) = '' THEN NULL
      WHEN REGEXP_CONTAINS(r.contract_type, r'O') THEN 'subscribe'
      WHEN REGEXP_CONTAINS(r.contract_type, r'X') THEN 'unsubscribe'
      WHEN REGEXP_CONTAINS(r.contract_type, r'계좌') THEN 'unsubscribe'
      ELSE NULL
    END AS subscribe_status,

    /* 1) 계약기간 구분 : year, month, free, trial
       주의: 유료/체험 판정은 아래 plan_status가 담당한다.
             이 컬럼은 계약기간 표현 전용이며 판정에 쓰지 않는다.
       (기존의 `pricing_plan = 'premium'` 분기는 실제 값이 대문자 'PREMIUM'이라
        한 번도 참이 된 적 없는 죽은 코드였으므로 제거함) */
    CASE
      WHEN REGEXP_CONTAINS(r.contract_period, r'무료') THEN 'trial'
      WHEN REGEXP_CONTAINS(r.contract_period, r'12') THEN 'year'
      WHEN REGEXP_CONTAINS(r.contract_period, r'1') THEN 'month'
      WHEN REGEXP_CONTAINS(r.contract_type, r'계좌') THEN 'year'
      WHEN r.contract_period IS NULL OR TRIM(r.contract_period) = '' THEN 'free'
      ELSE 'free'
    END AS contract_type_refine,

    /* 요금제 구분 — free / trial / plus / premium. 상호배타이며 합이 전체와 일치한다.
       요금제 판정은 이 컬럼 하나에서만 한다. plan_status와 is_paid_flag는 여기서 파생된다.
       - pricing_plan 실제 값은 대문자 FREE / PLUS / PREMIUM 3종
       - FREE는 is_trial_active와 무관하게 free.
         FREE + 체험중 조합은 user_count=0인 탈퇴/미개통 계정에서 체험 플래그가
         참으로 남은 것이지 실제 체험이 아니다.
       - PLUS/PREMIUM은 체험중이면 trial, 아니면 요금제 이름 그대로 */
    CASE
      WHEN r.pricing_plan IS NULL OR UPPER(TRIM(r.pricing_plan)) = 'FREE' THEN 'free'
      WHEN COALESCE(r.is_trial_active, FALSE) THEN 'trial'
      WHEN UPPER(TRIM(r.pricing_plan)) = 'PLUS' THEN 'plus'
      ELSE 'premium'
    END AS plan_detail,

    /* 중복기업 판정용 정규화 회사명.
       표기 흔들림만 제거한다 — 법인격 표기와 공백. 의미를 바꾸는 절단은 하지 않는다.
       지점·부서 표기를 자르면 서로 다른 고객사가 하나로 합쳐져 통계에서 사라진다.
       05 / 07 / 06_monthly_base가 모두 이 컬럼을 상속받아 같은 기준으로 판정한다.

       NORMALIZE(NFKC)를 먼저 거는 것이 중요하다. 실제 데이터에 전각 괄호가 섞여 있어
       (（주） 50건, (주） 4건, （주) 1건) 반각만 열거하면 그 회사들이 정규화에서 빠져나간다.
       NFKC가 전각 괄호를 반각으로, ㈜를 (주)로, 전각 영문을 반각으로 한 번에 바꿔주므로
       정규식에 변형을 하나씩 늘어놓을 필요가 없다. */
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        LOWER(TRIM(NORMALIZE(r.company_name, NFKC))),
        r'\(주\)|\(유\)|\(재\)|\(사\)|주식회사|유한회사|유한책임회사|재단법인|사단법인|농업회사법인|영어조합법인',
        ''),
      r'\s+', ''
    ) AS company_name_norm,

    /* 2) 초기 5회 평균 운행거리 */
    SAFE_DIVIDE(r.first_5_trips_distance, LEAST(r.trip_count_total, 5)) AS avg_distance_first_5_trips,

    /* 3) 운행 별 평균 운행거리 */
    SAFE_DIVIDE(r.total_distance, NULLIF(r.trip_count_total, 0)) AS avg_distance_per_trip,

    /* 누적 운행거리 존재 여부 플래그 */
    IF(total_distance IS NOT NULL AND total_distance > 0, 1, 0) AS has_total_distance_flag,

    /* last_trip_day_distance */
    CASE
      WHEN r.total_distance IS NULL THEN NULL
      WHEN LAG(r.total_distance) OVER (PARTITION BY r.company_code ORDER BY r.snapshot_date) IS NULL THEN NULL
      ELSE GREATEST(r.total_distance - LAG(r.total_distance) OVER (PARTITION BY r.company_code ORDER BY r.snapshot_date), 0)
    END AS last_trip_day_distance,

    /* 4) 가입일부터 첫 운행까지 소요일 */
    CASE
      WHEN r.first_trip_date_start IS NULL OR r.signup_date IS NULL THEN NULL
      ELSE DATE_DIFF(DATE(r.first_trip_date_start), r.signup_date, DAY)
    END AS days_to_first_trip,

    /* 회사별 가입일(최초) */
    MIN(r.signup_date) OVER (PARTITION BY r.company_code) AS signup_date_company,

    /* 최초 앱 로그인 스냅샷일 */
    MIN(CASE WHEN r.has_app_login THEN r.snapshot_date END)
      OVER (PARTITION BY r.company_code) AS app_first_login_snapshot_date,

    /* 가입일부터 첫 앱 로그인까지 소요일 */
    CASE
      WHEN MIN(r.signup_date) OVER (PARTITION BY r.company_code) IS NULL
        OR MIN(CASE WHEN r.has_app_login THEN r.snapshot_date END) OVER (PARTITION BY r.company_code) IS NULL
      THEN NULL
      ELSE DATE_DIFF(
        MIN(CASE WHEN r.has_app_login THEN r.snapshot_date END) OVER (PARTITION BY r.company_code),
        MIN(r.signup_date) OVER (PARTITION BY r.company_code),
        DAY
      )
    END AS days_to_first_app_login,

    /* 가입 후 경과일 */
    CASE WHEN r.signup_date IS NULL THEN NULL ELSE DATE_DIFF(r.snapshot_date, r.signup_date, DAY) END AS days_since_signup,

    /* 마지막 운행 후 경과일 */
    CASE WHEN r.last_trip_date_start IS NULL THEN NULL ELSE DATE_DIFF(r.snapshot_date, DATE(r.last_trip_date_start), DAY) END AS days_since_last_trip,

    /* 마지막 관리자 접속 후 경과일 */
    CASE WHEN r.pc_last_login_date IS NULL THEN NULL ELSE DATE_DIFF(r.snapshot_date, DATE(r.pc_last_login_date), DAY) END AS days_since_last_pc_login,

    -- Looker SUM용 0/1 플래그
    IFNULL(CAST(is_trial_active AS INT64), 0) AS is_trial_active_flag,
    IFNULL(CAST(has_app_login AS INT64), 0) AS has_app_login_flag,

    /* 테스트 계정 여부.
       회사명과 회사코드를 이어붙여 키워드로 판정한다.
       회사명은 company_name_norm과 같은 방식으로 정규화한다 — 전각/공백 변형으로
       키워드를 빠져나가는 것을 막기 위해서다. (2026-09-02 기준 정규화 전후 판정 결과는
       동일하다. 앞으로 `카 택 스`처럼 공백이 낀 이름이 들어올 때를 위한 방어다.) */
    REGEXP_CONTAINS(
      CONCAT(
        REGEXP_REPLACE(LOWER(NORMALIZE(IFNULL(r.company_name, ''), NFKC)), r'\s+', ''),
        ' ',
        LOWER(IFNULL(r.company_code, ''))
      ),
      r'(영티포|카택스|테스트|4424|유진의|조훈|낙현회사|퍼피또리)'
    )
    /* 수동으로 테스트 지정한 계정을 보탠다. 정규식이 놓친 것을 사람이 채운다.
       COALESCE가 필요하다. mo.override가 NULL이면 `FALSE OR NULL`이 FALSE가 아니라
       NULL이 되어(SQL 3값 논리) 수동 판정이 없는 계정까지 판정 불가가 된다. */
    OR COALESCE(mo.override, '') = 'test'
    AS is_test_account,

    /* 수동 판정 값을 그대로 노출한다. 05 / 06 / 07이 중복 판정에서 쓴다.
       test / exclude / keep 중 하나이거나 NULL. */
    mo.override AS manual_override,
    mo.reason   AS manual_override_reason,

    /* 업체관리 페이지 링크 */
    CONCAT('https://cds.carbeast.co.kr/admin/companyManager.php?service=biz&seq=', r.sequence_id) AS company_admin_url,

    /* 첫 운행 발생 여부 */
    IF(first_trip_date_start IS NOT NULL, 1, 0) AS has_first_trip_flag,

    /* 반복 운행 여부 */
    IF(trip_count_total >= 2, 1, 0) AS is_repeat_trip_flag,

    /* 회사별 최초 이탈(churn) 감지일
       05/07이 각자 churn_by_company CTE + LEFT JOIN으로 만들던 값을 여기로 올렸다.
       윈도우로 계산하면 JOIN이 필요 없다. */
    MIN(IF(r.is_churned, r.snapshot_date, NULL))
      OVER (PARTITION BY r.company_code) AS is_churned_date

  FROM `carbiz-6f7fc.signup_90days.raw_signup_90days` r
  /* 수동 판정. 데이터만으로 가릴 수 없는 것을 사람이 정해둔 목록이다.
     목록과 규칙은 00_manual_override.sql에 있다. */
  LEFT JOIN `carbiz-6f7fc.signup_90days.manual_override` mo
    ON mo.company_code = r.company_code
),

/* 유료판정 + 최초 유료 snapshot_date
   판정 기준은 plan_status 하나뿐이다. 05/07은 여기서 만든 is_paid_flag를
   그대로 상속받아 쓰며, 각자 다시 정의하지 않는다. */
paid AS (
  SELECT
    b.*,

    /* 요금제 상태 롤업 — plus/premium을 paid로 묶는다.
       판정은 plan_detail에서 이미 끝났고 여기서는 묶기만 한다. */
    IF(b.plan_detail IN ('plus', 'premium'), 'paid', b.plan_detail) AS plan_status,

    /* 유료 여부 (Looker SUM용 0/1) */
    IF(b.plan_detail IN ('plus', 'premium'), 1, 0) AS is_paid_flag,

    /* 회사별 최초 유료 스냅샷일 */
    MIN(IF(b.plan_detail IN ('plus', 'premium'), b.snapshot_date, NULL))
      OVER (PARTITION BY b.company_code) AS paid_first_snapshot_date

  FROM base b
),

final AS (
  SELECT
    paid.*,

    /* 사용자 별 평균 운행거리 */
    SAFE_DIVIDE(paid.last_trip_day_distance, NULLIF(paid.user_count, 0)) AS avg_distance_per_user,

    /* ✅ 가입 후 결제(대체: 최초 유료 snapshot)까지 소요기간 */
    CASE
      WHEN paid.signup_date_company IS NULL OR paid.paid_first_snapshot_date IS NULL THEN NULL
      ELSE DATE_DIFF(paid.paid_first_snapshot_date, paid.signup_date_company, DAY)
    END AS days_since_paid,

    /* ---- 아래는 05/07이 각자 계산하던 공통 파생이다. 한 곳에서만 만든다. ---- */

    /* 가입일부터 이탈까지 소요일 */
    CASE
      WHEN paid.is_churned_date IS NULL OR paid.signup_date IS NULL THEN NULL
      ELSE DATE_DIFF(paid.is_churned_date, paid.signup_date, DAY)
    END AS days_to_churn,

    /* 가입 연 / 월 / 연월 (signup_date 기준) */
    EXTRACT(YEAR FROM paid.signup_date) AS signup_year,
    EXTRACT(MONTH FROM paid.signup_date) AS signup_month,
    FORMAT_DATE('%Y-%m', paid.signup_date) AS signup_year_month,

    /* 첫 운행 전에 이탈했는지 (BOOL) */
    CASE
      WHEN paid.is_churned_date IS NULL THEN NULL
      WHEN paid.first_trip_date_start IS NULL THEN TRUE
      ELSE DATE(paid.is_churned_date) < DATE(paid.first_trip_date_start)
    END AS churn_before_activation,

    /* 첫 운행 전에 이탈했는지 (SUM용 FLAG: 0/1) */
    CASE
      WHEN paid.is_churned_date IS NULL THEN 0
      WHEN paid.first_trip_date_start IS NULL THEN 1
      WHEN DATE(paid.is_churned_date) < DATE(paid.first_trip_date_start) THEN 1
      ELSE 0
    END AS churn_before_activation_flag,

    /* 선결제 여부 — 예약일 존재 + 체험 활성. 유료(is_paid_flag)와는 별개 지표다. */
    IF(paid.is_booking_date IS NOT NULL AND paid.is_trial_active_flag = 1, 1, 0) AS is_pre_paid_flag,

    /* 탈퇴기업 여부 — user_count = 0 */
    COALESCE(paid.user_count = 0, FALSE) AS is_withdrawn_company,

    /* 실제 라이선스 수.
       무료·체험 기업은 라이선스가 100으로 기본 지급되어 실제 사용 규모가 아니다.
       그래서 무료·체험은 차량수로 대체하고, 유료만 license_count를 그대로 쓴다.
       집계에서 라이선스를 셀 때는 항상 이 컬럼을 쓴다. */
    IF(paid.plan_status = 'paid', paid.license_count, paid.vehicle_count) AS license_count_adjusted,

    /* 회사별 최신 스냅샷 순번 (1 = 최신).
       05는 rn = 1로 좁히고, 07은 좁히지 않는다. */
    ROW_NUMBER() OVER (
      PARTITION BY paid.company_code
      ORDER BY paid.snapshot_date DESC, paid.data_collection_time DESC
    ) AS rn

  FROM paid
)

SELECT * FROM final;