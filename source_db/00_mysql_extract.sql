/* ============================================================================
   00. MySQL 원천 추출 — 개발팀 실행용
   ----------------------------------------------------------------------------
   이 파일은 BigQuery가 아니라 서비스 MySQL에서 실행한다. 우리는 실행하지 않는다.
   결과를 parquet으로 아래 경로에 올리면 01번 외부 테이블이 그대로 읽는다.

       gs://cartax-biz_source_db/<테이블>/dt=YYYY-MM-DD/*.parquet

   컬럼 별칭을 여기서 이미 snake_case로 맞춰 둔다. parquet 단계에서 이름이
   정리되어 있으면 BigQuery 쪽 적재가 SELECT * 한 줄로 끝난다.
   (policy/10_naming.md — 「이름이 틀린 입력은 적재하면서 바로잡는다」)

   [최초 전량]  아래 :from / :to 를 넓게 잡고 연도별로 나눠 실행
   [일 증분]    :from = 전일 00:00:00, :to = 당일 00:00:00  (KST)

   ※ 증분 기준은 전부 updateTime 이다. createTime 이 아니다.
     환불·취소·삭제는 기존 행을 수정하므로 createTime 으로는 절대 못 잡는다.

   ※ 주의 — createTime 신뢰 구간
     payment seq 1~10 의 createTime 이 전부 '2017-05-15 19:48:10' 이다.
     그 시점에 데이터를 이관한 흔적이고, beginDate 는 2016년이다.
     2017-05-15 이전 행의 createTime 은 생성 시각이 아니다. 기간 분석에는
     payment.beginDate, company 는 별도 확인이 필요하다.
   ========================================================================= */


/* ---------------------------------------------------------------------------
   [1순위] payment — 결제 1건이 1행
   매출이 추정에서 사실이 된다. 지금은 요금제 정가를 곱해 역산하고 있다.

   제외한 것: aid, memo(자유 입력), finally(미사용), paymentTempSeq,
             merchant_uid / imp_uid / receipt_url (PG 식별자·URL. 분석 용도 없음)
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS payment_id,
    companySeq                        AS company_seq,
    contractType                      AS contract_type,      -- OFFICIAL/UPGRADE/CHANGE/AGAIN/RENEW/SCHEDULE/RETRY/addCar/add/default
    state                             AS state,              -- Apply / Complete / Cancel
    `type`                            AS product_code,       -- ※ 샘플 전부 'SC0999'. 의미 확인 필요
    licenceQuantity                   AS license_count,
    term                              AS term_month,
    beginDate                         AS contract_begin_date,
    endDate                           AS contract_end_date,
    totalAmount                       AS total_amount,
    discountAmount                    AS discount_amount,
    amount                            AS amount,
    discount                          AS discount,
    refundAmount                      AS refund_amount,
    level                             AS plan_level,
    useCredit                         AS use_credit,
    returnCredit                      AS return_credit,
    (isVoucher = 1)                   AS is_voucher,         -- 비대면 바우처
    (admin = 'Y')                     AS is_admin_created,
    (complete = 1)                    AS is_deposit_confirmed,-- 무통장 입금 확인
    createTime                        AS created_at,
    updateTime                        AS updated_at
FROM payment
WHERE updateTime >= :from AND updateTime < :to;


/* ---------------------------------------------------------------------------
   [1순위] paySchedule — 정기결제 예약과 그 결과
   status='E' + errorMsg 가 결제 실패의 유일한 기록이다.

   errorMsg 는 PG 응답 메시지로 보이지만 자유 텍스트다.
   개인정보가 섞여 오는지 최초 적재 후 실제 값을 확인한다. (설계안 10-④)

   제외한 것: value (내부 옵션 연결용)
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS schedule_id,
    companySeq                        AS company_seq,
    `type`                            AS product_type,       -- pricePlan(요금제) / cartaxCare(카택스 케어)
    amount                            AS amount,             -- 크레딧 미반영, 부가세 포함
    level                             AS plan_level,
    licenceQuantity                   AS license_count,
    payCycle                          AS pay_cycle,          -- M / Y
    payDate                           AS pay_date,
    status                            AS status,             -- R:예약 Y:완료 C:취소 E:에러
    errorMsg                          AS error_message,
    createTime                        AS created_at,
    updateTime                        AS updated_at
FROM paySchedule
WHERE updateTime >= :from AND updateTime < :to;


/* ---------------------------------------------------------------------------
   [1순위] companyPayState — 기업의 현재 결제 상태 (기업당 1행)
   설계안 05번의 「현재 상태는 반드시 받아야 한다」가 이 테이블 하나로 끝난다.
   결제 이력만으로는 대신할 수 없다 — 무료·체험 기업 81%는 결제 이력이 아예 없다.

   ※ free 컬럼은 이름과 의미가 반대다 (Y = 무료체험 '불가능').
     헷갈리는 채로 두면 반드시 사고가 난다. 적재 시점에 뒤집어 바로잡는다.
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS pay_state_id,
    companySeq                        AS company_seq,
    (autoPay = 'Y')                   AS is_auto_pay,        -- 자동결제 설정 = 계약 종료일에 자동 갱신
    payMethod                         AS pay_method,         -- CARD / TRANS / FREE
    previousPayMethod                 AS previous_pay_method,
    payCycle                          AS pay_cycle,
    beginDate                         AS contract_begin_date,
    endDate                           AS contract_end_date,
    licenceQuantity                   AS license_count,
    (free = 'N')                      AS is_trial_available, -- ★ 원본 반전. 원본 Y=불가능
    (freeIng = 'Y')                   AS is_trial_active,
    freeBeginDate                     AS trial_begin_date,
    freeEndDate                       AS trial_end_date,
    freeCancelDate                    AS trial_cancel_date,  -- 무료체험 중 구독 취소. 이탈 선행지표
    (unlimited = 'Y')                 AS is_downgrade_exempt,
    createTime                        AS created_at,
    updateTime                        AS updated_at
FROM companyPayState
WHERE updateTime >= :from AND updateTime < :to;


/* ---------------------------------------------------------------------------
   [1순위] companyPayStateHistory — 결제 상태 변경 이력
   「지난 10년간 상태를 쌓은 적이 없어 소급 분석이 안 된다」의 해답.
   이 테이블이 있으면 과거 임의 시점의 계약 상태를 재구성할 수 있고,
   first_payment_* / last_payment_* 같은 요약 컬럼을 따로 받을 이유가 없다.
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS history_id,
    targetSeq                         AS pay_state_id,       -- companyPayState.seq
    companySeq                        AS company_seq,
    (autoPay = 'Y')                   AS is_auto_pay,
    payMethod                         AS pay_method,
    previousPayMethod                 AS previous_pay_method,
    payCycle                          AS pay_cycle,
    beginDate                         AS contract_begin_date,
    endDate                           AS contract_end_date,
    licenceQuantity                   AS license_count,
    (free = 'N')                      AS is_trial_available, -- ★ 원본 반전
    (freeIng = 'Y')                   AS is_trial_active,
    freeBeginDate                     AS trial_begin_date,
    freeEndDate                       AS trial_end_date,
    freeCancelDate                    AS trial_cancel_date,
    (unlimited = 'Y')                 AS is_downgrade_exempt,
    createTime                        AS created_at,
    updateTime                        AS updated_at
FROM companyPayStateHistory
WHERE updateTime >= :from AND updateTime < :to;


/* ---------------------------------------------------------------------------
   [1순위] freeExperienceHistory — 무료체험 부여 이력
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS trial_id,
    companySeq                        AS company_seq,
    beginDate                         AS trial_begin_date,
    endDate                           AS trial_end_date,
    licenceQuantity                   AS license_count,
    level                             AS plan_level,
    createTime                        AS created_at,
    updateTime                        AS updated_at
FROM freeExperienceHistory
WHERE updateTime >= :from AND updateTime < :to;


/* ---------------------------------------------------------------------------
   [2순위] company — 기업 마스터 (기업당 1행)
   corporateNumber(사업자등록번호)가 오면 중복 판정에서 회사명 정규화·법인격
   제거·수동 판정 목록이 대부분 불필요해진다. 지금은 문자열로 추측하고 있고
   합친 것이 맞는지 검증할 방법이 없다.

   ★ gid = 구글애널리틱스 clientId.
     GA4 의 user_pseudo_id 와 이어지면 마케팅 유입 → 가입이 한 줄로 연결된다.
     설계안 10-② 에서 「가장 큰 구멍」이라고 쓴 부분이 일부 메워진다.

   [개인정보 — 원본에 있으나 가져오지 않는다]
     password, ikey, autoLoginKey   인증 정보
     adminName, invoiceeCEOName     개인 성명
     tel, phone                     연락처
     adminMemo, cartaxMemo          자유 입력. 이름·연락처·거래처가 섞인다
     email                          → 도메인만 가져온다
     address                        → 시/도 + 시/군/구 2어절만 가져온다

   [미사용 — 원본 주석에 명시. 가져오지 않는다]
     autoStartMessage, autoStopMessage, autoApproval, sort, marketer,
     corporateDocName, logoEnabled, licenceReceipt, licenceOil

   [설정 18개를 받는 이유]
     선별 기준 4(쓸 분석 없으면 받지 않는다)에 걸리는 것처럼 보이나,
     기준의 예외인 「되돌릴 수 없는 것」에 해당한다. 설정값은 현재 상태만 있고
     변경 이력이 어디에도 남지 않는다. 오늘 안 받으면 어제 값은 영영 사라진다.
     기업은 2.5만 행이라 용량 부담이 없다.
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS company_seq,
    cid                               AS company_code,
    name                              AS company_name,
    corporateNumber                   AS company_number,     -- 사업자등록번호. 일부 시점 이후 가입 건만 존재
    businessType                      AS business_type,
    level                             AS plan_level,
    enabled                           AS enabled_state,      -- Y:사용 N:미사용 X:탈퇴
    (enabled = 'X')                   AS is_withdrawn,
    createTime                        AS signup_date,        -- ※ 이관 시점 이전은 신뢰 불가. 상단 주석 참조
    lastLogin                         AS last_login_at,
    joinPath                          AS join_path,          -- 가입 경로
    joinType                          AS join_device,        -- pc / mobile / ios / and
    coalitionCompany                  AS coalition_company,  -- none / hyundaicard / wp(네이버 워크플레이스) / wr(웍스)
    gid                               AS ga_client_id,       -- ★ GA4 user_pseudo_id 연결 고리
    SUBSTRING_INDEX(email, '@', -1)   AS email_domain,       -- 전체 주소 아님. 도메인만
    SUBSTRING_INDEX(address, ' ', 2)  AS address_region,     -- 시/도 + 시/군/구 까지만
    smsCnt                            AS invite_sms_count,
    defaultOilMileage                 AS default_oil_mileage,
    defaultPurpose                    AS default_purpose,
    -- 설정 (제품 활용 깊이 지표)
    individualAuth                    AS setting_individual_auth,
    corporationAuth                   AS setting_corporation_auth,
    lockDeviceChange                  AS setting_lock_device_change,
    timeBlind                         AS setting_time_blind,
    noWorkBlind                       AS setting_no_work_blind,
    lockDate                          AS setting_lock_date,
    lockTime                          AS setting_lock_time,
    lockDistance                      AS setting_lock_distance,
    lockTotalDistance                 AS setting_lock_total_distance,
    lockSaveMapPoint                  AS setting_save_map_point,   -- A전체 Y출도착 N선택 X미저장 C차량별
    isOtherDrivingAuth                AS setting_other_driving_auth,
    privacyMode                       AS setting_privacy_mode,     -- none / user / car / all
    userJoinEmail                     AS setting_user_join_email,
    deviceChangeEmail                 AS setting_device_change_email,
    denyWeeklyReport                  AS setting_deny_weekly_report,
    changeModal                       AS setting_upgrade_modal,
    isDisabledAutoAuth                AS setting_auto_auth_disabled,
    insuranceAdsAgreement             AS setting_insurance_ads_agree,
    updateTime                        AS updated_at
FROM company
WHERE updateTime >= :from AND updateTime < :to;


/* ---------------------------------------------------------------------------
   [1순위] drivingLog — 운행 1건이 1행. 10년 약 2,500만 행
   아하 모먼트와 이탈 신호가 전부 여기 있다.

   최초 전량은 연도별로 나눠 실행한다 (회당 약 477 MB):
     WHERE startDate >= '2016-01-01' AND startDate < '2017-01-01'
   증분은 updateTime 기준.

   [가져오지 않는다 — 개인정보]
     name, departmentName, dutyName      개인 성명·부서·직책
     startAddress, stopAddress           출발·도착 주소
     startLatitude/Longitude,
     stopLatitude/Longitude              좌표
     bigo                                자유 입력 메모
   → 2,500만 행에서 varchar(85)×2 + double×4 + varchar(45)×3 + text 를 빼는
     것이라 용량과 개인정보 위험이 동시에 크게 줄어든다.

   [가져오지 않는다 — 원천에 남아 있어 나중에 받아도 된다]
     maxSpeed, avgSpeed, safePoint,
     accelerationCount, decelerationCount,
     quickStartCount, quickStopCount     안전운전 지표. 쓸 분석이 아직 없다
     startDistance, stopDistance         distance 로 계산된다
     departmentSeq                       부서 테이블이 아직 없어 해석 불가
     startDrivingType, stopDrivingType   drivingType 과 중복으로 보인다
     uuid, saveMapPoint, mergeCount,
     overlapSeq, overlapComplete,
     duplication, disConnectTime,
     gpsFakerPackage, strByte
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS trip_id,
    companySeq                        AS company_seq,
    carSeq                            AS vehicle_seq,
    userUid                           AS user_uid,
    startDate                         AS trip_date,          -- 파티션 키
    startTime                         AS start_time,
    stopTime                          AS stop_time,
    distance                          AS distance,
    gpsDistance                       AS gps_distance,       -- >0 이면 GPS 실운행. 수기 입력과 가른다
    hyundaiDistance                   AS connected_car_distance,
    drivingTime                       AS driving_time,
    purpose                           AS purpose_name,
    (autoStart = 'Y')                 AS is_auto_start,      -- 자동 운행
    drivingType                       AS driving_type,       -- 수동 / 비콘 / 블루투스 / 전원
    (isAdminCreated = 'Y')            AS is_admin_created,   -- 관리자가 만든 운행 ↔ 직원 운행
    status                            AS approval_status,    -- N미승인 Y승인 X반려 T임시
    (deleteState = 'Y')               AS is_deleted,         -- soft delete
    (isMerge = 'Y')                   AS is_merge_parent,
    parentSeq                         AS merge_parent_seq,   -- 합쳐진 운행. 중복 집계 방지에 필요
    (isOverlap = 'Y')                 AS is_overlap_parent,
    overlapState                      AS overlap_state,      -- NONE / OWN / REJECT
    hyundaiSave                       AS connected_car_save, -- N / H / K / G
    gpsFaked                          AS gps_faked,          -- GPS 조작 검출
    oilAmount                         AS oil_amount,
    tollAmount                        AS toll_amount,
    gitaAmount                        AS etc_amount,
    versionName                       AS app_version,
    createTime                        AS created_at,
    updateTime                        AS updated_at
FROM drivingLog
WHERE updateTime >= :from AND updateTime < :to;


/* ---------------------------------------------------------------------------
   [1순위] deleteDrivingLog — 물리 삭제분의 식별자만
   drivingLog 는 deleteState='Y' 로 soft delete 하지만, 물리 삭제된 행은
   증분 조회로 영영 잡히지 않는다. 우리 쪽에 유령 행이 남는다.
   seq 만 받아서 raw_trip 에서 삭제 표시한다.
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS trip_id,
    companySeq                        AS company_seq,
    startDate                         AS trip_date,   -- raw_trip 파티션 프루닝에 필요
    updateTime                        AS updated_at
FROM deleteDrivingLog
WHERE updateTime >= :from AND updateTime < :to;


/* ---------------------------------------------------------------------------
   [3순위] car — 차량 1대가 1행. 약 45만 행
   이탈 선행지표가 아님이 실증됐다 (이탈 14개사 중 차량 86%가 그대로).
   원천에 계속 남아 있으므로 나중에 받아도 된다. 1·2순위 적재가 안정된 뒤.

   [가져오지 않는다] number(차량번호 = 준식별자), memo(자유 입력), imageUrl
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS vehicle_seq,
    companySeq                        AS company_seq,
    useUid                            AS assigned_user_uid,
    carGroupSeq                       AS vehicle_group_seq,
    model                             AS model,
    carType                           AS vehicle_type,
    auth                              AS auth_scope,          -- All / Section
    oilTypeSeq                        AS oil_type_seq,
    oilMileage                        AS oil_mileage,
    displacement                      AS displacement,
    totalDistance                     AS total_distance,
    useCount                          AS use_count,
    (beaconMajor > 0 OR beaconMinor > 0) AS has_beacon,
    (carMonitoringPermission = 'Y')   AS has_monitoring,
    monitroingCount                   AS monitoring_count,
    savePointType                     AS save_point_type,
    (isPrivacy = 'Y')                 AS is_privacy,
    buyType                           AS buy_type,
    buyDate                           AS buy_date,
    insuranceStartDate                AS insurance_begin_date,
    insuranceEndDate                  AS insurance_end_date,
    depreciationType                  AS depreciation_type,
    depreciationDate                  AS depreciation_date,
    supportFundCost                   AS support_fund_cost,
    regularCheckExpiry                AS regular_check_expiry,
    enabled                           AS enabled_state,
    deleteDate                        AS deleted_at,          -- 차량 삭제·중지일
    createTime                        AS created_at,
    updateTime                        AS updated_at
FROM car
WHERE updateTime >= :from AND updateTime < :to;
