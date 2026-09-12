/* ============================================================================
   01. External Table — GCS parquet 을 가리키기만 한다
   ----------------------------------------------------------------------------
   경로 규칙:  gs://cartax-biz_source_db/<테이블>/dt=YYYY-MM-DD/*.parquet
   dt 는 파일을 올린 날짜다. 데이터의 날짜가 아니다.

   require_hive_partition_filter = TRUE 이므로 조회할 때 반드시 dt 를 건다.
   빼먹으면 전체 스캔이 아니라 에러가 난다. 실수로 전 기간을 읽는 사고를 막는다.

   컬럼은 정의하지 않는다. parquet 스키마를 그대로 따라간다.
   추출 쿼리(00번)에서 이미 snake_case 로 별칭을 줬기 때문이다.
   ========================================================================= */

-- ── 1순위 ────────────────────────────────────────────────────────────────
CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.source_db.ext_payment`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (format = 'PARQUET',
  uris = ['gs://cartax-biz_source_db/payment/dt=*'],
  hive_partition_uri_prefix = 'gs://cartax-biz_source_db/payment/',
  require_hive_partition_filter = TRUE);

CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.source_db.ext_pay_schedule`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (format = 'PARQUET',
  uris = ['gs://cartax-biz_source_db/pay_schedule/dt=*'],
  hive_partition_uri_prefix = 'gs://cartax-biz_source_db/pay_schedule/',
  require_hive_partition_filter = TRUE);

CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.source_db.ext_company_pay_state`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (format = 'PARQUET',
  uris = ['gs://cartax-biz_source_db/company_pay_state/dt=*'],
  hive_partition_uri_prefix = 'gs://cartax-biz_source_db/company_pay_state/',
  require_hive_partition_filter = TRUE);

CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.source_db.ext_company_pay_state_history`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (format = 'PARQUET',
  uris = ['gs://cartax-biz_source_db/company_pay_state_history/dt=*'],
  hive_partition_uri_prefix = 'gs://cartax-biz_source_db/company_pay_state_history/',
  require_hive_partition_filter = TRUE);

CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.source_db.ext_trial_history`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (format = 'PARQUET',
  uris = ['gs://cartax-biz_source_db/trial_history/dt=*'],
  hive_partition_uri_prefix = 'gs://cartax-biz_source_db/trial_history/',
  require_hive_partition_filter = TRUE);

CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.source_db.ext_trip`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (format = 'PARQUET',
  uris = ['gs://cartax-biz_source_db/trip/dt=*'],
  hive_partition_uri_prefix = 'gs://cartax-biz_source_db/trip/',
  require_hive_partition_filter = TRUE);

CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.source_db.ext_trip_deleted`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (format = 'PARQUET',
  uris = ['gs://cartax-biz_source_db/trip_deleted/dt=*'],
  hive_partition_uri_prefix = 'gs://cartax-biz_source_db/trip_deleted/',
  require_hive_partition_filter = TRUE);

-- ── 2순위 ────────────────────────────────────────────────────────────────
CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.source_db.ext_company`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (format = 'PARQUET',
  uris = ['gs://cartax-biz_source_db/company/dt=*'],
  hive_partition_uri_prefix = 'gs://cartax-biz_source_db/company/',
  require_hive_partition_filter = TRUE);

-- ── 3순위 — 1·2순위 적재가 안정된 뒤에 만든다 ────────────────────────────
-- CREATE OR REPLACE EXTERNAL TABLE `carbiz-6f7fc.source_db.ext_vehicle`
-- WITH PARTITION COLUMNS (dt DATE)
-- OPTIONS (format = 'PARQUET',
--   uris = ['gs://cartax-biz_source_db/vehicle/dt=*'],
--   hive_partition_uri_prefix = 'gs://cartax-biz_source_db/vehicle/',
--   require_hive_partition_filter = TRUE);
