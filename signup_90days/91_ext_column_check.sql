CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.signup_90days._tmp_onefile_schema`
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://cartax-biz_signup_90days/dt=2026-01-29/20260129.parquet']
);

SELECT column_name, data_type
FROM `carbiz-6f7fc.signup_90days.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = '_tmp_onefile_schema'
ORDER BY ordinal_position;
