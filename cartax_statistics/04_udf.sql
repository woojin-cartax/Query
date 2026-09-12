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
