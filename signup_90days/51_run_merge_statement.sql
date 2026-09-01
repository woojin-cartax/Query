SELECT
  DATE(creation_time, "Asia/Seoul") AS run_date,
  job_id,
  user_email,
  statement_type,
  state,                         -- DONE / RUNNING
  error_result.reason            AS error_reason,
  error_result.message           AS error_message,
  total_bytes_processed,
  total_slot_ms,
  creation_time,
  end_time
FROM `region-asia-northeast3`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE
  statement_type = 'MERGE'
  AND creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY creation_time DESC;
