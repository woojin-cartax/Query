/* ============================================================================
   04. UDF — 여러 뷰가 공유하는 변환
   ----------------------------------------------------------------------------
   같은 판정을 뷰마다 따로 쓰면 정의가 갈라진다. 실제로 signup_90days 에서
   유료 판정이 is_paid_cond / is_paid_flag 두 벌로 갈려 같은 KPI 뷰 안에서
   유료 기업 수가 494 와 496 으로 나온 적이 있다.
   (policy/10_naming.md — 같은 판정을 두 컬럼으로 만들지 않는다)

   뷰(05~09)보다 먼저 만들어야 한다. 번호가 그 순서다.
   ========================================================================= */

/* 요금제 등급 숫자 → 이름.
   1 = free, 2 = plus, 3 = premium  (2026-09-12 확인)
   company.level / payment.level / paySchedule.level / freeExperienceHistory.level
   이 모두 같은 체계를 쓴다.
   기존 signup_90days 의 pricing_plan (FREE/PLUS/PREMIUM) 과 대응한다. */
CREATE OR REPLACE FUNCTION `carbiz-6f7fc.cartax_statistics.plan_name`(plan_level INT64)
RETURNS STRING
AS (
  CASE plan_level
    WHEN 1 THEN 'free'
    WHEN 2 THEN 'plus'
    WHEN 3 THEN 'premium'
    ELSE NULL          -- 새 등급이 생기면 NULL 로 드러난다. 조용히 뭉개지 않는다
  END
);


/* 최고관리자 여부.
   role_seq = 0 이 최고관리자다. 나머지는 사용자로 분류한다. (2026-09-12 확인)
   role 테이블이 없어 0 이외의 값이 서로 어떻게 다른지는 모른다.
   지금 필요한 구분은 관리자/사용자 둘뿐이라 그것만 만든다.

   ※ IFNULL 로 감싸 NULL 을 FALSE 로 떨어뜨린다.
     감싸지 않으면 role_seq 가 NULL 인 사용자의 is_super_admin 이 NULL 이 되고,
     COUNTIF(is_super_admin) 에도 COUNTIF(NOT is_super_admin) 에도 안 잡혀
     관리자도 사용자도 아닌 채로 집계에서 사라진다.
     (signup_90days 에서 `FALSE OR NULL` 로 is_test_account 가 통째로 NULL 이
      됐던 것과 같은 종류의 사고다.)
     대신 그 NULL 이 조용히 묻히므로 90_check.sql 13번이 개수를 따로 센다. */
CREATE OR REPLACE FUNCTION `carbiz-6f7fc.cartax_statistics.is_super_admin`(role_seq INT64)
RETURNS BOOL
AS (
  IFNULL(role_seq = 0, FALSE)
);
