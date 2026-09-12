/* ============================================================================
   02. Native Table — 실제 데이터를 저장한다
   ----------------------------------------------------------------------------
   ※ 이 파일을 통째로 실행하지 않는다. 선두가 DROP TABLE 이다.
     필요한 블록만 골라서 실행한다.

   [파티션 방침]  설계안 08번
     trip 만 월별로 나눈다. BigQuery 는 테이블당 파티션 4,000개가 한계다.
     일별로 나누면 11년이고, 10년을 백필하는 순간 1년 뒤에 막힌다.
     월별이면 10년이 120개다. trip 은 기준을 바꿔 재계산할 때만 훑고
     그때는 어차피 전 기간을 본다.

     나머지는 작아서 파티션이 필요 없다. 클러스터만 건다.
     payment 50만 행, company 2.5만 행.

   [증분 적재의 전제]  설계안 07번
     고유 ID + updated_at + 삭제 표시. 셋 다 원천에 있는 것을 확인했다.
     - 고유 ID    : seq (전 테이블)
     - updated_at : updateTime (전 테이블, CURRENT_TIMESTAMP 기본값)
     - 삭제 표시  : drivingLog.deleteState / payment.state='Cancel'
                    / company.enabled='X' / car.deleteDate
       물리 삭제가 일어나는 곳은 drivingLog 하나뿐이고, 그것은
       deleteDrivingLog 테이블로 따로 잡는다.
   ========================================================================= */


/* ── trip — 운행 원본. 10년 2,500만 행 ─────────────────────────────────── */
DROP TABLE IF EXISTS `carbiz-6f7fc.source_db.raw_trip`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.source_db.raw_trip`
(
  trip_id                  INT64    NOT NULL,
  company_seq              INT64,
  vehicle_seq              INT64,
  user_uid                 STRING,
  trip_date                DATE,
  start_time               DATETIME,
  stop_time                DATETIME,
  distance                 INT64,
  gps_distance             INT64,
  connected_car_distance   INT64,
  driving_time             FLOAT64,
  purpose_name             STRING,
  is_auto_start            BOOL,
  driving_type             STRING,
  is_admin_created         BOOL,
  approval_status          STRING,
  is_deleted               BOOL,
  is_merge_parent          BOOL,
  merge_parent_seq         INT64,
  is_overlap_parent        BOOL,
  overlap_state            STRING,
  connected_car_save       STRING,
  gps_faked                INT64,
  oil_amount               INT64,
  toll_amount              INT64,
  etc_amount               INT64,
  app_version              STRING,
  created_at               DATETIME,
  updated_at               DATETIME,
  loaded_at                TIMESTAMP   -- 우리가 적재한 시각. 원천에 없는 값
)
PARTITION BY DATE_TRUNC(trip_date, MONTH)
CLUSTER BY company_seq, trip_date
OPTIONS (
  description = '운행 원본. MySQL drivingLog. 1행 = 운행 1건. 주소·좌표·메모·성명은 수집하지 않는다.',
  require_partition_filter = TRUE
);


/* ── payment — 결제 이력 ──────────────────────────────────────────────── */
DROP TABLE IF EXISTS `carbiz-6f7fc.source_db.raw_payment`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.source_db.raw_payment`
(
  payment_id               INT64    NOT NULL,
  company_seq              INT64,
  contract_type            STRING,   -- OFFICIAL/UPGRADE/CHANGE/AGAIN/RENEW/SCHEDULE/RETRY/addCar/add/default
  state                    STRING,   -- Apply / Complete / Cancel
  product_code             STRING,
  license_count            INT64,
  term_month               INT64,
  contract_begin_date      DATE,
  contract_end_date        DATE,
  total_amount             INT64,
  discount_amount          INT64,
  amount                   INT64,
  discount                 INT64,
  refund_amount            INT64,
  plan_level               INT64,
  use_credit               INT64,
  return_credit            INT64,
  is_voucher               BOOL,
  is_admin_created         BOOL,
  is_deposit_confirmed     BOOL,
  created_at               DATETIME,
  updated_at               DATETIME,
  loaded_at                TIMESTAMP
)
CLUSTER BY company_seq, contract_begin_date
OPTIONS (description = '결제 이력. MySQL payment. 1행 = 결제 1건. contract_type 으로 갱신·재시도·업그레이드가 구분된다.');


/* ── pay_schedule — 정기결제 예약과 결과. 실패 기록이 여기 있다 ────────── */
DROP TABLE IF EXISTS `carbiz-6f7fc.source_db.raw_pay_schedule`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.source_db.raw_pay_schedule`
(
  schedule_id              INT64    NOT NULL,
  company_seq              INT64,
  product_type             STRING,   -- pricePlan / cartaxCare
  amount                   INT64,
  plan_level               INT64,
  license_count            INT64,
  pay_cycle                STRING,   -- M / Y
  pay_date                 DATETIME,
  status                   STRING,   -- R예약 Y완료 C취소 E에러
  error_message            STRING,   -- 결제 실패 사유
  created_at               DATETIME,
  updated_at               DATETIME,
  loaded_at                TIMESTAMP
)
CLUSTER BY company_seq, pay_date
OPTIONS (description = '정기결제 예약·결과. MySQL paySchedule. status=E 와 error_message 가 결제 실패의 유일한 기록이다.');


/* ── company_pay_state — 기업의 현재 결제 상태 (기업당 1행) ───────────── */
DROP TABLE IF EXISTS `carbiz-6f7fc.source_db.raw_company_pay_state`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.source_db.raw_company_pay_state`
(
  pay_state_id             INT64    NOT NULL,
  company_seq              INT64,
  is_auto_pay              BOOL,
  pay_method               STRING,   -- CARD / TRANS / FREE
  previous_pay_method      STRING,
  pay_cycle                STRING,
  contract_begin_date      DATE,
  contract_end_date        DATE,
  license_count            INT64,
  is_trial_available       BOOL,     -- ★ 원본 free 컬럼을 뒤집은 값
  is_trial_active          BOOL,
  trial_begin_date         DATE,
  trial_end_date           DATE,
  trial_cancel_date        DATE,
  is_downgrade_exempt      BOOL,
  created_at               DATETIME,
  updated_at               DATETIME,
  loaded_at                TIMESTAMP
)
CLUSTER BY company_seq
OPTIONS (description = '기업 현재 결제 상태. MySQL companyPayState. 결제 이력으로 대신할 수 없다 — 무료·체험 기업 81%는 결제 이력이 없다.');


/* ── company_pay_state_history — 결제 상태 변경 이력 ──────────────────── */
DROP TABLE IF EXISTS `carbiz-6f7fc.source_db.raw_company_pay_state_history`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.source_db.raw_company_pay_state_history`
(
  history_id               INT64    NOT NULL,
  pay_state_id             INT64,
  company_seq              INT64,
  is_auto_pay              BOOL,
  pay_method               STRING,
  previous_pay_method      STRING,
  pay_cycle                STRING,
  contract_begin_date      DATE,
  contract_end_date        DATE,
  license_count            INT64,
  is_trial_available       BOOL,
  is_trial_active          BOOL,
  trial_begin_date         DATE,
  trial_end_date           DATE,
  trial_cancel_date        DATE,
  is_downgrade_exempt      BOOL,
  created_at               DATETIME,
  updated_at               DATETIME,
  loaded_at                TIMESTAMP
)
CLUSTER BY company_seq, created_at
OPTIONS (description = '결제 상태 변경 이력. MySQL companyPayStateHistory. 과거 임의 시점의 계약 상태를 재구성할 수 있다.');


/* ── trial_history — 무료체험 부여 이력 ──────────────────────────────── */
DROP TABLE IF EXISTS `carbiz-6f7fc.source_db.raw_trial_history`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.source_db.raw_trial_history`
(
  trial_id                 INT64    NOT NULL,
  company_seq              INT64,
  trial_begin_date         DATE,
  trial_end_date           DATE,
  license_count            INT64,
  plan_level               INT64,
  created_at               DATETIME,
  updated_at               DATETIME,
  loaded_at                TIMESTAMP
)
CLUSTER BY company_seq
OPTIONS (description = '무료체험 부여 이력. MySQL freeExperienceHistory.');


/* ── trip_deleted — 물리 삭제된 운행의 식별자 ────────────────────────── */
DROP TABLE IF EXISTS `carbiz-6f7fc.source_db.raw_trip_deleted`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.source_db.raw_trip_deleted`
(
  trip_id                  INT64    NOT NULL,
  company_seq              INT64,
  trip_date                DATE,
  updated_at               DATETIME,
  loaded_at                TIMESTAMP
)
CLUSTER BY company_seq
OPTIONS (description = '물리 삭제된 운행. MySQL deleteDrivingLog. raw_trip 에 유령 행이 남는 것을 막는다.');


/* ── company — 기업 마스터 (기업당 1행) ──────────────────────────────── */
DROP TABLE IF EXISTS `carbiz-6f7fc.source_db.raw_company`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.source_db.raw_company`
(
  company_seq                    INT64  NOT NULL,
  company_code                   STRING,
  company_name                   STRING,
  company_number                 STRING,   -- 사업자등록번호. 특정 시점 이후 가입 건만 존재
  business_type                  STRING,
  plan_level                     INT64,
  enabled_state                  STRING,   -- Y사용 N미사용 X탈퇴
  is_withdrawn                   BOOL,
  signup_date                    DATETIME, -- ※ 2017-05-15 이관 이전은 신뢰 불가
  last_login_at                  DATETIME,
  join_path                      STRING,
  join_device                    STRING,
  coalition_company              STRING,
  ga_client_id                   STRING,   -- GA4 user_pseudo_id 연결 고리
  email_domain                   STRING,   -- 도메인만. 주소 전체는 수집하지 않는다
  address_region                 STRING,   -- 시/도 + 시/군/구 까지만
  invite_sms_count               INT64,
  default_oil_mileage            NUMERIC,
  default_purpose                STRING,
  setting_individual_auth        STRING,
  setting_corporation_auth       STRING,
  setting_lock_device_change     STRING,
  setting_time_blind             STRING,
  setting_no_work_blind          STRING,
  setting_lock_date              STRING,
  setting_lock_time              STRING,
  setting_lock_distance          STRING,
  setting_lock_total_distance    STRING,
  setting_save_map_point         STRING,
  setting_other_driving_auth     STRING,
  setting_privacy_mode           STRING,
  setting_user_join_email        STRING,
  setting_device_change_email    STRING,
  setting_deny_weekly_report     STRING,
  setting_upgrade_modal          STRING,
  setting_auto_auth_disabled     STRING,
  setting_insurance_ads_agree    STRING,
  updated_at                     DATETIME,
  loaded_at                      TIMESTAMP
)
CLUSTER BY company_seq, company_code
OPTIONS (description = '기업 마스터. MySQL company. 인증정보·성명·연락처·자유입력 메모는 수집하지 않는다. 이메일은 도메인만, 주소는 시군구까지만.');


/* ── login_pc — PC·브라우저 로그인 이력 ──────────────────────────────── */
DROP TABLE IF EXISTS `carbiz-6f7fc.source_db.raw_login_pc`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.source_db.raw_login_pc`
(
  login_id                 INT64    NOT NULL,
  company_seq              INT64,
  company_code             STRING,
  user_uid                 STRING,
  platform                 STRING,
  browser                  STRING,
  browser_version          STRING,
  referer                  STRING,   -- 유입 경로
  is_success               BOOL,
  error_message            STRING,   -- 로그인 실패 사유
  created_at               DATETIME,
  updated_at               DATETIME, -- 원본 컬럼명은 updateTIme (오타). 적재하며 바로잡는다
  loaded_at                TIMESTAMP
)
PARTITION BY DATETIME_TRUNC(created_at, MONTH)
CLUSTER BY company_seq, user_uid
OPTIONS (description = 'PC·브라우저 로그인 이력. MySQL loginBrowserHistory. IP·userAgent 는 수집하지 않는다.');


/* ── login_app — 앱(모바일) 로그인 이력 ──────────────────────────────
   ※ 원본에 updateTime 이 없다. append-only 라 증분 기준이 created_at 이다.
   ※ company_seq 가 없다. user 테이블이 와야 기업에 붙는다.                 */
DROP TABLE IF EXISTS `carbiz-6f7fc.source_db.raw_login_app`;
CREATE OR REPLACE TABLE `carbiz-6f7fc.source_db.raw_login_app`
(
  login_id                 INT64    NOT NULL,
  user_uid                 STRING,
  device_id                STRING,
  os_type                  STRING,   -- Android / iOS / ETC
  os_version               STRING,
  app_version              STRING,
  country                  STRING,
  language                 STRING,
  device_model             STRING,
  created_at               DATETIME,
  loaded_at                TIMESTAMP
)
PARTITION BY DATETIME_TRUNC(created_at, MONTH)
CLUSTER BY user_uid, created_at
OPTIONS (description = '앱 로그인 이력. MySQL userLoginHistory. updateTime 이 없어 증분 기준이 created_at 이다.');
