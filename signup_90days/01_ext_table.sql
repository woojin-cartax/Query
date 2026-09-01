-- 1. 기존 External Table 삭제
DROP EXTERNAL TABLE IF EXISTS `carbiz-6f7fc.signup_90days.ext_signup_90days`;

-- 2. 생성
CREATE EXTERNAL TABLE `carbiz-6f7fc.signup_90days.ext_signup_90days`
WITH PARTITION COLUMNS (
  dt DATE
)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://cartax-biz_signup_90days/dt=*'],
  hive_partition_uri_prefix = 'gs://cartax-biz_signup_90days/',
  require_hive_partition_filter = TRUE

);
