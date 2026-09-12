/* ============================================================================
   50. 실행 기록 테이블
   ----------------------------------------------------------------------------
   90일 스냅샷에서 34일간(2026-06-30~08-03) 무증상 실패가 있었다.
   GCS 업로드가 멈췄는데 MERGE 는 0행으로 성공했고 전부 SUCCESS 로 기록됐다.
   08-04에야 발견됐고 2026-07-29 는 영구 결손이 될 뻔했다.

   그래서 상태를 세 가지로 나눈다.
     SUCCESS  적재됐다
     EMPTY    쿼리는 성공했으나 0행이다 ← 이게 무증상 실패다
     FAIL     예외가 났다
   ========================================================================= */

CREATE TABLE IF NOT EXISTS `carbiz-6f7fc.source_db.query_run_log`
(
  target_date    DATE,        -- 적재 대상일 (GCS dt)
  job_name       STRING,      -- 예약 쿼리 이름
  target_table   STRING,      -- 적재 대상 테이블
  status         STRING,      -- SUCCESS / EMPTY / FAIL
  merged_rows    INT64,       -- MERGE 가 건드린 행 수 (신규 + 갱신)
  updated_rows   INT64,       -- 갱신분 (현재 미사용. 신규/갱신 분리가 필요해지면 채운다)
  error_message  STRING,
  logged_at      TIMESTAMP
)
CLUSTER BY target_date, target_table
OPTIONS (description = 'source_db 적재 실행 기록. EMPTY 는 성공이 아니라 무증상 실패 신호다.');
