/* ============================================================================
   00. MySQL 원천 추출 — 개발팀 실행용
   ----------------------------------------------------------------------------
   이 파일은 BigQuery가 아니라 서비스 MySQL에서 실행한다. 우리는 실행하지 않는다.
   결과를 parquet으로 아래 경로에 올리면 01번 외부 테이블이 그대로 읽는다.

       gs://cartax-biz_cartax_statistics/<테이블>/dt=YYYY-MM-DD/*.parquet

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

   [설정은 두 개만 받는다]
     lockSaveMapPoint  경로 저장 범위 (A전체 / Y출도착 / N선택 / X미저장 / C차량별)
     privacyMode       사생활 보호 (none / user / car / all)
     둘 다 「수집하는 데이터의 양 자체」를 정하는 설정이라, 운행 데이터가 왜
     비어 있는지를 설명한다. 나머지 16개는 쓸 분석이 없어 뺐다 (선별 기준 4).
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
    -- 설정 — 수집 범위를 정하는 둘만
    lockSaveMapPoint                  AS setting_save_map_point,   -- A전체 Y출도착 N선택 X미저장 C차량별
    privacyMode                       AS setting_privacy_mode,     -- none / user / car / all
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
    departmentSeq                     AS department_seq,     -- department 테이블로 해석된다
    startDate                         AS trip_date,          -- 파티션 키
    startTime                         AS start_time,
    stopTime                          AS stop_time,
    distance                          AS distance,
    gpsDistance                       AS gps_distance,       -- >0 이면 GPS 실운행. 수기 입력과 가른다
    hyundaiDistance                   AS connected_car_distance,
    drivingTime                       AS driving_time,
    purpose                           AS purpose_code,     -- 코드다. 이름이 아니다. purpose 테이블로 해석한다
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


/* ---------------------------------------------------------------------------
   [1순위] loginBrowserHistory — PC·브라우저 로그인 이력
   설계안의 pc_first_login_date / pc_last_login_date / admin_login_count_total 이
   전부 여기서 나온다. 받을 필요 없이 우리가 계산한다.

   success/errorMsg 로 로그인 실패까지 남는다. 실패가 반복되는 기업은
   접근 자체가 막혀 있는 것이고, 이탈 원인이 제품 불만이 아니라 로그인일 수 있다.

   referer 는 유입 경로다. 마케팅 분석에 직결된다.

   [가져오지 않는다]
     clientIp    암호화돼 있어도 로그인 시도 IP다. 쓸 분석이 없다
     userAgent   raw 문자열. platform / browser / version 으로 이미 파싱돼 있다
     parent      브라우저 정보로 확인됨. browser 와 중복이라 불필요

   ※ 원본 컬럼명이 updateTIme 다 (대문자 I). 오타지만 원본은 고칠 수 없다.
     적재하면서 updated_at 으로 바로잡는다.
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS login_id,
    companySeq                        AS company_seq,
    cid                               AS admin_cid,          -- 관리자 계정 id. company.cid
    uid                               AS user_uid,
    platform                          AS platform,
    browser                           AS browser,
    version                           AS browser_version,
    referer                           AS referer,
    (success = 1)                     AS is_success,
    errorMsg                          AS error_message,
    createTime                        AS created_at,
    updateTIme                        AS updated_at        -- ★ 원본 오타. 그대로 읽어 바로잡는다
FROM loginBrowserHistory
WHERE updateTIme >= :from AND updateTIme < :to;


/* ---------------------------------------------------------------------------
   [1순위] userLoginHistory — 앱(모바일) 로그인 이력
   설계안의 has_app_login 이 여기서 나온다. 그 이상으로, 기기·OS·앱 버전이
   로그인마다 남아 버전 채택과 기기 교체를 추적할 수 있다.

   ※ updateTime 이 없다. createTime 만 NOT NULL 이다.
     로그인은 한 번 일어나면 고쳐지지 않는 append-only 사건이라 그렇다.
     증분 기준을 createTime 으로 잡는다. 다른 테이블과 다르니 주의.

   ※ companySeq 가 없다. uid 뿐이다.
     기업에 붙이려면 uid → 기업 대응이 필요한데 user 테이블이 아직 없다.
     임시로 drivingLog(userUid + companySeq)로 이을 수는 있으나 운행을 한 번도
     안 한 사용자가 빠진다. user 테이블을 받는 것이 맞다.

   [가져오지 않는다] 없음. 10컬럼 전부 분석에 쓴다.
     deviceId 는 준식별자지만 기기 교체 추적에 필요해 유지한다.
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS login_id,
    uid                               AS user_uid,
    deviceId                          AS device_id,
    osType                            AS os_type,           -- Android / iOS / ETC
    osVersion                         AS os_version,
    versionName                       AS app_version,
    country                           AS country,
    language                          AS language,
    model                             AS device_model,
    createTime                        AS created_at
FROM userLoginHistory
WHERE createTime >= :from AND createTime < :to;   -- ★ updateTime 이 없다


/* ---------------------------------------------------------------------------
   [1순위] user — 사용자 1명이 1행
   uid → 기업 대응이 여기서 풀린다. 지금까지 userLoginHistory 와 drivingLog 를
   기업에 붙일 방법이 운행 기록뿐이었고, 운행을 한 번도 안 한 사용자가 빠졌다.

   42컬럼 중 13개만 받는다. 기기·OS·언어·권한 세부·커넥티드카 상태 등은
   쓸 분석이 없어 뺐다 (선별 기준 4). 원천에 남아 있으므로 나중에 받을 수 있다.

   ★ 사용자 확산이 제대로 측정된다.
     관리자 1명만 쓰는 회사와 직원까지 쓰는 회사는 완전히 다른 고객이다.
     enabled 로 승인·미승인·탈퇴·정지가 갈리므로 「실제 쓰는 사용자 수」를 센다.

   ※ roleSeq = 0 이 최고관리자다. 나머지는 전부 사용자다. (2026-09-12 확인)
     role 테이블은 받을 필요가 없다 — 우리에게 필요한 구분이 둘뿐이다.

   [가져오지 않는다 — 개인정보]
     password, autoLoginKey, pushId   인증·푸시 토큰
     name                             개인 성명
     carNumber                        개인 차량번호 (준식별자)
     wp_login_id, wp_emp_id           워크플레이스 식별자
     deviceId, pushId                 기기·푸시 토큰
     email                            → 도메인만 가져온다
                                        (포털 도메인인지 회사 도메인인지 보려고)

   [가져오지 않는다 — 쓸 분석이 없다]
     totalDistance, carModel, deviceChangeCount, osType, osVersion,
     versionName, model, country, language, secondary, developerAuth,
     agreeTerms, isPrivacy, corporationAuth, individualAuth,
     hyundaiState, hyundaiCarSeq, companyName,
     dutySeq(직급이라 분석에 쓰지 않는다. duty 테이블도 받을 필요 없다)
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS user_id,
    uid                               AS user_uid,
    orgUid                            AS origin_user_uid,
    companySeq                        AS company_seq,
    departmentSeq                     AS department_seq,
    roleSeq                           AS role_seq,           -- 0 = 최고관리자. 나머지는 전부 사용자
    enabled                           AS enabled_state,      -- Y승인 N미승인 C기기변경 X탈퇴 B사용중지
    (enabled = 'X')                   AS is_withdrawn,
    SUBSTRING_INDEX(email, '@', -1)   AS email_domain,       -- 전체 주소 아님
    lastLogin                         AS last_login_at,
    lastLoginDate                     AS last_login_date,
    createTime                        AS created_at,
    updateTime                        AS updated_at
FROM `user`
WHERE updateTime >= :from AND updateTime < :to;


/* ---------------------------------------------------------------------------
   [2순위] department — 부서. 계층 구조다
   drivingLog.departmentSeq 와 user.departmentSeq 를 해석한다.
   부서 개수와 조직 깊이(depth)로 도입 규모를 본다.

   ※ 부서명(name / fullName)은 받지 않는다. 부서를 몇 개 만들었고 계층이 몇
     단계인지만 알면 되고, 이름은 어느 집계에도 안 들어간다. 소규모 회사에서
     「홍길동팀」처럼 사람 이름이 들어올 수 있는 위험도 같이 사라진다.
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS department_seq,
    companySeq                        AS company_seq,
    parentSeq                         AS parent_department_seq,
    depth                             AS depth,
    createTime                        AS created_at,
    updateTime                        AS updated_at
FROM department
WHERE updateTime >= :from AND updateTime < :to;


/* ---------------------------------------------------------------------------
   [2순위] purpose — 운행목적 정의. 기업마다 따로 만든다
   drivingLog.purpose 가 코드로 들어오는데 그것을 해석할 유일한 테이블이다.

   ★ companySeq 가 있다. 운행목적은 전사 공통이 아니라 기업별 정의다.
     같은 코드가 기업마다 다른 뜻일 수 있으므로 해석은 반드시
     (company_seq, 코드) 쌍으로 한다. 코드만으로 전사 집계하면 서로 다른
     목적이 한 덩어리가 된다.

   ※ drivingLog.purpose 가 셋 중 무엇과 붙는지 아직 확인되지 않았다.
     purposeCode / purposeType / purposeName 을 다 받아서 90_check.sql 16번으로
     매칭률을 재고, 확인된 쪽으로 07_view_trip.sql 의 조인 키를 확정한다.

   [가져오지 않는다] sort (화면 표시 순서. 분석에 안 쓴다)
   ------------------------------------------------------------------------- */
SELECT
    seq                               AS purpose_seq,
    companySeq                        AS company_seq,
    purposeCode                       AS purpose_code,
    purposeType                       AS purpose_type,
    purposeName                       AS purpose_name,
    (purposeDefault = 'Y')            AS is_default,
    purposeState                      AS purpose_state,      -- Y활성 N비활성 X삭제
    (isGenerally = 1)                 AS is_general_business,-- 국세청 양식의 일반업무 포함 여부
    createTime                        AS created_at,
    updateTime                        AS updated_at
FROM purpose
WHERE updateTime >= :from AND updateTime < :to;
