/* ============================================================================
   01. External Table — GCS parquet 을 가리키기만 한다
   ----------------------------------------------------------------------------
   gs://cartax-biz-statistics/dt=YYYY-MM-DD/YYYYMMDD.parquet
   하루 1파일, 약 1.9 MB, 37컬럼, 2만 행. 2026-09-15 부터 빠진 날 없다.
   업로드 22:48 KST · data_collection_time 전 행 동일 22:00:02

   signup_90days 와 같은 모양이고 모집단만 전 고객사로 넓어졌다.
   컬럼 34개가 공통이고 차이는 셋 — 아래 02번 머리주석 참조.

   require_hive_partition_filter = TRUE 이므로 조회할 때 반드시 dt 를 건다.
   빼먹으면 전체 스캔이 아니라 에러가 난다. 실수로 전 기간을 읽는 사고를 막는다.

   컬럼은 정의하지 않는다. parquet 스키마를 그대로 따라간다.
   ========================================================================= */

CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.signup_statistics.ext_signup_statistics`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://cartax-biz-statistics/dt=*'],
  hive_partition_uri_prefix = 'gs://cartax-biz-statistics/',
  require_hive_partition_filter = TRUE
);
