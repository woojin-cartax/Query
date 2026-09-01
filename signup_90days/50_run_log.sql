CREATE TABLE IF NOT EXISTS `carbiz-6f7fc.signup_90days.query_run_log` (
  run_date DATE,
  query_name STRING,
  target_table STRING,
  status STRING,          -- SUCCESS / FAIL
  inserted_rows INT64,
  updated_rows INT64,
  error_message STRING,
  executed_at TIMESTAMP
);
