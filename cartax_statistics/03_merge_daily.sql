/* ============================================================================
   03. 일 증분 적재 — 예약 쿼리 본문
   ----------------------------------------------------------------------------
   하루 한 번, 전일에 올라온 dt 폴더를 읽어 raw_* 에 MERGE 한다.
   성공·실패·적재 행수를 query_run_log 에 남긴다.

   ※ 90일 스냅샷의 34일 무증상 실패(2026-06-30~08-03)가 있었다.
     GCS 업로드가 멈췄는데 MERGE 는 0행으로 성공했고 전부 SUCCESS 로 기록됐다.
     그래서 「행이 0이면 EMPTY」를 판정에 넣는다. 성공했다는 기록만으로는
     파이프라인이 살아 있다는 증거가 되지 않는다.

   [소급 적재]  아래 target_dt 를 바꿔 실행한다. 파일을 복제하지 않는다.
   ========================================================================= */

DECLARE target_dt DATE DEFAULT DATE_SUB(CURRENT_DATE("Asia/Seoul"), INTERVAL 1 DAY);
--DECLARE target_dt DATE DEFAULT DATE('2026-09-01');   -- 소급 적재용 (주석 해제)

DECLARE trip_cnt, payment_cnt, schedule_cnt, paystate_cnt,
        paystate_hist_cnt, trial_cnt, company_cnt, deleted_cnt,
        login_admin_cnt, login_app_cnt, user_cnt, dept_cnt,
        purpose_cnt INT64 DEFAULT 0;

/* raw_trip 은 require_partition_filter = TRUE 다. MERGE 의 ON 절과 UPDATE 의
   WHERE 절에 파티션 컬럼(trip_date) 범위를 반드시 걸어야 한다.
   스칼라 서브쿼리로 걸면 프루닝이 안 된다 — 2,500만 행을 매일 전량 스캔하게 된다.
   먼저 변수에 담아 상수처럼 쓴다. 배포 전 dry-run 으로 스캔 바이트를 확인할 것. */
DECLARE trip_from, trip_to DATE;
DECLARE del_from, del_to   DATE;
DECLARE pc_from,  pc_to    DATETIME;
DECLARE app_from, app_to   DATETIME;

/* INSERT ROW 는 원본과 대상의 컬럼 이름·순서가 완전히 같아야 성립한다.
   raw_* 에만 있는 loaded_at 을 USING 절에서 만들어 붙이는 이유다.
   추출 쿼리(00번)의 별칭 순서를 02번 DDL 과 맞춰 두었으니 이 전제가 유지된다.
   00번이나 02번의 컬럼 순서를 바꾸면 여기가 조용히 깨진다. */

BEGIN

  SET (trip_from, trip_to) = (
    SELECT AS STRUCT IFNULL(MIN(trip_date), CURRENT_DATE("Asia/Seoul")),
                     IFNULL(MAX(trip_date), CURRENT_DATE("Asia/Seoul"))
    FROM `carbiz-6f7fc.cartax_statistics.ext_trip` WHERE dt = target_dt);

  SET (del_from, del_to) = (
    SELECT AS STRUCT IFNULL(MIN(trip_date), CURRENT_DATE("Asia/Seoul")),
                     IFNULL(MAX(trip_date), CURRENT_DATE("Asia/Seoul"))
    FROM `carbiz-6f7fc.cartax_statistics.ext_trip_deleted` WHERE dt = target_dt);

  SET (pc_from, pc_to) = (
    SELECT AS STRUCT IFNULL(MIN(created_at), CURRENT_DATETIME("Asia/Seoul")),
                     IFNULL(MAX(created_at), CURRENT_DATETIME("Asia/Seoul"))
    FROM `carbiz-6f7fc.cartax_statistics.ext_login_admin` WHERE dt = target_dt);

  SET (app_from, app_to) = (
    SELECT AS STRUCT IFNULL(MIN(created_at), CURRENT_DATETIME("Asia/Seoul")),
                     IFNULL(MAX(created_at), CURRENT_DATETIME("Asia/Seoul"))
    FROM `carbiz-6f7fc.cartax_statistics.ext_login_app` WHERE dt = target_dt);

  /* ── trip ────────────────────────────────────────────────────────────
     파티션 프루닝이 핵심이다. ON 절에만 trip_id 를 걸면 대상 테이블 전체를
     훑는다. 2,500만 행이 쌓인 뒤에는 매일 전량 스캔이 된다.
     들어온 데이터의 운행월 범위를 먼저 구해서 T 쪽을 그 범위로 자른다.       */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_trip` T
  USING (
    SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_trip` WHERE dt = target_dt
  ) S
  ON  T.trip_id = S.trip_id
  AND T.trip_date BETWEEN trip_from AND trip_to
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    company_seq = S.company_seq, vehicle_seq = S.vehicle_seq, user_uid = S.user_uid,
    department_seq = S.department_seq, trip_date = S.trip_date, start_time = S.start_time, stop_time = S.stop_time,
    distance = S.distance, gps_distance = S.gps_distance,
    connected_car_distance = S.connected_car_distance, driving_time = S.driving_time,
    purpose_code = S.purpose_code, is_auto_start = S.is_auto_start,
    driving_type = S.driving_type, is_admin_created = S.is_admin_created,
    approval_status = S.approval_status, is_deleted = S.is_deleted,
    is_merge_parent = S.is_merge_parent, merge_parent_seq = S.merge_parent_seq,
    is_overlap_parent = S.is_overlap_parent, overlap_state = S.overlap_state,
    connected_car_save = S.connected_car_save, gps_faked = S.gps_faked,
    oil_amount = S.oil_amount, toll_amount = S.toll_amount, etc_amount = S.etc_amount,
    app_version = S.app_version, created_at = S.created_at, updated_at = S.updated_at,
    loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET trip_cnt = @@row_count;

  /* ── trip_deleted — 물리 삭제분을 raw_trip 에도 반영 ──────────────── */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_trip_deleted` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_trip_deleted` WHERE dt = target_dt) S
  ON T.trip_id = S.trip_id
  WHEN MATCHED THEN UPDATE SET
    company_seq = S.company_seq, trip_date = S.trip_date,
    updated_at = S.updated_at, loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET deleted_cnt = @@row_count;

  UPDATE `carbiz-6f7fc.cartax_statistics.raw_trip` T
  SET is_deleted = TRUE, loaded_at = CURRENT_TIMESTAMP()
  WHERE T.trip_date BETWEEN del_from AND del_to
    AND NOT T.is_deleted
    AND T.trip_id IN (
      SELECT trip_id FROM `carbiz-6f7fc.cartax_statistics.ext_trip_deleted` WHERE dt = target_dt
    );

  /* ── payment ─────────────────────────────────────────────────────── */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_payment` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_payment` WHERE dt = target_dt) S
  ON T.payment_id = S.payment_id
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    company_seq = S.company_seq, contract_type = S.contract_type, state = S.state,
    product_code = S.product_code, license_count = S.license_count, term_month = S.term_month,
    contract_begin_date = S.contract_begin_date, contract_end_date = S.contract_end_date,
    total_amount = S.total_amount, discount_amount = S.discount_amount, amount = S.amount,
    discount = S.discount, refund_amount = S.refund_amount, plan_level = S.plan_level,
    use_credit = S.use_credit, return_credit = S.return_credit, is_voucher = S.is_voucher,
    is_admin_created = S.is_admin_created, is_deposit_confirmed = S.is_deposit_confirmed,
    created_at = S.created_at, updated_at = S.updated_at, loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET payment_cnt = @@row_count;

  /* ── pay_schedule ────────────────────────────────────────────────── */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_pay_schedule` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_pay_schedule` WHERE dt = target_dt) S
  ON T.schedule_id = S.schedule_id
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    company_seq = S.company_seq, product_type = S.product_type, amount = S.amount,
    plan_level = S.plan_level, license_count = S.license_count, pay_cycle = S.pay_cycle,
    pay_date = S.pay_date, status = S.status, error_message = S.error_message,
    created_at = S.created_at, updated_at = S.updated_at, loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET schedule_cnt = @@row_count;

  /* ── company_pay_state ───────────────────────────────────────────── */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_company_pay_state` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_company_pay_state` WHERE dt = target_dt) S
  ON T.pay_state_id = S.pay_state_id
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    company_seq = S.company_seq, is_auto_pay = S.is_auto_pay, pay_method = S.pay_method,
    previous_pay_method = S.previous_pay_method, pay_cycle = S.pay_cycle,
    contract_begin_date = S.contract_begin_date, contract_end_date = S.contract_end_date,
    license_count = S.license_count, is_trial_available = S.is_trial_available,
    is_trial_active = S.is_trial_active, trial_begin_date = S.trial_begin_date,
    trial_end_date = S.trial_end_date, trial_cancel_date = S.trial_cancel_date,
    is_downgrade_exempt = S.is_downgrade_exempt,
    created_at = S.created_at, updated_at = S.updated_at, loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET paystate_cnt = @@row_count;

  /* ── company_pay_state_history ───────────────────────────────────── */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_company_pay_state_history` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_company_pay_state_history` WHERE dt = target_dt) S
  ON T.history_id = S.history_id
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    pay_state_id = S.pay_state_id, company_seq = S.company_seq, is_auto_pay = S.is_auto_pay,
    pay_method = S.pay_method, previous_pay_method = S.previous_pay_method,
    pay_cycle = S.pay_cycle, contract_begin_date = S.contract_begin_date,
    contract_end_date = S.contract_end_date, license_count = S.license_count,
    is_trial_available = S.is_trial_available, is_trial_active = S.is_trial_active,
    trial_begin_date = S.trial_begin_date, trial_end_date = S.trial_end_date,
    trial_cancel_date = S.trial_cancel_date, is_downgrade_exempt = S.is_downgrade_exempt,
    created_at = S.created_at, updated_at = S.updated_at, loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET paystate_hist_cnt = @@row_count;

  /* ── trial_history ───────────────────────────────────────────────── */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_trial_history` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_trial_history` WHERE dt = target_dt) S
  ON T.trial_id = S.trial_id
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    company_seq = S.company_seq, trial_begin_date = S.trial_begin_date,
    trial_end_date = S.trial_end_date, license_count = S.license_count,
    plan_level = S.plan_level, created_at = S.created_at, updated_at = S.updated_at,
    loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET trial_cnt = @@row_count;

  /* ── company ─────────────────────────────────────────────────────── */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_company` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_company` WHERE dt = target_dt) S
  ON T.company_seq = S.company_seq
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    company_code = S.company_code, company_name = S.company_name,
    company_number = S.company_number, business_type = S.business_type,
    plan_level = S.plan_level, enabled_state = S.enabled_state, is_withdrawn = S.is_withdrawn,
    signup_date = S.signup_date, last_login_at = S.last_login_at, join_path = S.join_path,
    join_device = S.join_device, coalition_company = S.coalition_company,
    ga_client_id = S.ga_client_id, email_domain = S.email_domain,
    address_region = S.address_region, invite_sms_count = S.invite_sms_count,
    setting_save_map_point = S.setting_save_map_point,
    setting_privacy_mode = S.setting_privacy_mode,
    updated_at = S.updated_at, loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET company_cnt = @@row_count;

  /* ── login_admin ────────────────────────────────────────────────────── */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_login_admin` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_login_admin` WHERE dt = target_dt) S
  ON  T.login_id = S.login_id
  AND T.created_at BETWEEN pc_from AND pc_to
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    company_seq = S.company_seq, admin_cid = S.admin_cid, user_uid = S.user_uid,
    platform = S.platform, browser = S.browser, browser_version = S.browser_version,
    referer = S.referer, is_success = S.is_success, error_message = S.error_message,
    created_at = S.created_at, updated_at = S.updated_at, loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET login_admin_cnt = @@row_count;

  /* ── login_app ───────────────────────────────────────────────────
     원본에 updateTime 이 없다. 로그인은 한 번 일어나면 고쳐지지 않는
     append-only 사건이라 갱신 분기가 아예 없다. 새 행만 넣는다.          */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_login_app` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_login_app` WHERE dt = target_dt) S
  ON  T.login_id = S.login_id
  AND T.created_at BETWEEN app_from AND app_to
  WHEN NOT MATCHED THEN INSERT ROW;
  SET login_app_cnt = @@row_count;

  /* ── user ────────────────────────────────────────────────────────
     uid → 기업 대응의 원천. 다른 무엇보다 먼저 맞아야 한다.            */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_user` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_user` WHERE dt = target_dt) S
  ON T.user_id = S.user_id
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    user_uid = S.user_uid, origin_user_uid = S.origin_user_uid,
    company_seq = S.company_seq, department_seq = S.department_seq,
    role_seq = S.role_seq, enabled_state = S.enabled_state,
    is_withdrawn = S.is_withdrawn, email_domain = S.email_domain,
    last_login_at = S.last_login_at, last_login_date = S.last_login_date,
    created_at = S.created_at, updated_at = S.updated_at, loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET user_cnt = @@row_count;

  /* ── department ──────────────────────────────────────────────────── */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_department` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_department` WHERE dt = target_dt) S
  ON T.department_seq = S.department_seq
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    company_seq = S.company_seq, parent_department_seq = S.parent_department_seq,
    depth = S.depth, created_at = S.created_at, updated_at = S.updated_at, loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET dept_cnt = @@row_count;

  /* ── purpose ─────────────────────────────────────────────────────── */
  MERGE `carbiz-6f7fc.cartax_statistics.raw_purpose` T
  USING (SELECT * EXCEPT(dt), CURRENT_TIMESTAMP() AS loaded_at
    FROM `carbiz-6f7fc.cartax_statistics.ext_purpose` WHERE dt = target_dt) S
  ON T.purpose_seq = S.purpose_seq
  WHEN MATCHED AND S.updated_at > T.updated_at THEN UPDATE SET
    company_seq = S.company_seq, purpose_code = S.purpose_code,
    purpose_type = S.purpose_type, purpose_name = S.purpose_name,
    is_default = S.is_default, purpose_state = S.purpose_state,
    is_general_business = S.is_general_business,
    created_at = S.created_at, updated_at = S.updated_at, loaded_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT ROW;
  SET purpose_cnt = @@row_count;

  /* ── 실행 기록 ───────────────────────────────────────────────────── */
  INSERT INTO `carbiz-6f7fc.cartax_statistics.query_run_log`
  SELECT target_dt, 'cartax_statistics_merge', tbl, IF(cnt = 0, 'EMPTY', 'SUCCESS'),
         cnt, CAST(NULL AS INT64), CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  FROM UNNEST([
    STRUCT('raw_trip' AS tbl, trip_cnt AS cnt),
    ('raw_trip_deleted',              deleted_cnt),
    ('raw_payment',                   payment_cnt),
    ('raw_pay_schedule',              schedule_cnt),
    ('raw_company_pay_state',         paystate_cnt),
    ('raw_company_pay_state_history', paystate_hist_cnt),
    ('raw_trial_history',             trial_cnt),
    ('raw_company',                   company_cnt),
    ('raw_login_admin',                  login_admin_cnt),
    ('raw_login_app',                 login_app_cnt),
    ('raw_user',                      user_cnt),
    ('raw_department',                dept_cnt),
    ('raw_purpose',                   purpose_cnt)
  ]);

EXCEPTION WHEN ERROR THEN
  INSERT INTO `carbiz-6f7fc.cartax_statistics.query_run_log`
  VALUES (target_dt, 'cartax_statistics_merge', CAST(NULL AS STRING), 'FAIL',
          CAST(NULL AS INT64), CAST(NULL AS INT64),
          @@error.message, CURRENT_TIMESTAMP());
  RAISE USING MESSAGE = @@error.message;
END;
