/* ============================================================================
   50. 실행 기록 테이블
   ----------------------------------------------------------------------------
   signup_90days 에서 34일간(2026-06-30~08-03) 무증상 실패가 있었다.
   GCS 업로드가 멈췄는데 MERGE 는 0행으로 성공했고 전부 SUCCESS 로 기록됐다.

   그래서 상태를 셋으로 나눈다.
     SUCCESS  적재됐다
     EMPTY    쿼리는 성공했으나 0행이다 ← 이게 무증상 실패다
     FAIL     예외가 났다
   ========================================================================= */

CREATE TABLE IF NOT EXISTS `carbiz-6f7fc.signup_statistics.query_run_log`
(
  target_date    DATE,
  job_name       STRING,
  target_table   STRING,
  status         STRING,      -- SUCCESS / EMPTY / FAIL
  inserted_rows  INT64,       -- 신규 적재분
  updated_rows   INT64,       -- 갱신분 (같은 날짜 재적재 시)
  error_message  STRING,
  logged_at      TIMESTAMP
)
CLUSTER BY target_date
OPTIONS (description = 'signup_statistics 적재 기록. EMPTY 는 성공이 아니라 무증상 실패 신호다.');
