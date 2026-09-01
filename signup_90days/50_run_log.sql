CREATE TABLE IF NOT EXISTS `carbiz-6f7fc.signup_90days.query_run_log` (
  run_date DATE,
  query_name STRING,
  target_table STRING,
  status STRING,          -- SUCCESS / EMPTY / FAIL
                          --   EMPTY = 쿼리는 정상이나 적재 결과가 0행.
                          --           GCS에 원본이 안 올라온 날을 구분한다.
                          -- 주의: 이 파일은 CREATE TABLE IF NOT EXISTS 다.
                          --       테이블이 이미 있으므로 위 주석 변경은 배포되지 않는다.
                          --       실제 값은 03_merge_daily.sql이 쓴다.
  inserted_rows INT64,
  updated_rows INT64,
  error_message STRING,
  executed_at TIMESTAMP
);
