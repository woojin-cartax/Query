# cartax_statistics — 서비스 MySQL 원천 사본

전체 고객사 데이터를 원천에 가까운 형태로 받아 BigQuery에 쌓는다.
집계는 받지 않고 우리가 만든다. 기준이 바뀌어도 데이터를 다시 받지 않기 위해서다.

설계 근거는 「일별 스냅샷 설계안 (2판)」에 있다.
현재 운영 중인 90일 스냅샷(`../signup_90days/`)은 **끄지 않는다.** 당분간 병행한다.

## 상태

**아직 아무것도 배포되지 않았다.** MySQL 추출이 시작되기 전의 초안이다.
데이터셋 `cartax_statistics`, 버킷 `gs://cartax-biz_cartax_statistics/` 도 아직 만들지 않았다.
이름은 확정 전이라 바꿀 수 있다.

## 파일

| 파일 | 어디서 실행하나 | 무엇을 하나 |
|---|---|---|
| `00_mysql_extract.sql` | **서비스 MySQL** (개발팀) | 원천 추출. 우리는 실행하지 않는다 |
| `01_ext_table.sql` | BigQuery | GCS parquet을 가리키는 외부 테이블 |
| `02_raw_table.sql` | BigQuery | 네이티브 테이블. **선두가 DROP이라 통째 실행 금지** |
| `03_merge_daily.sql` | BigQuery 예약 쿼리 | 일 증분 MERGE |
| `04_udf.sql` | BigQuery | 공용 변환. `plan_name()`. **뷰보다 먼저 만든다** |
| `05_view_payment.sql` | BigQuery | 결제 사실 뷰. 성공·실패·환불·시도 성격 판정 |
| `06_view_company.sql` | BigQuery | 기업 마스터 + 현재 결제 상태 |
| `07_view_trip.sql` | BigQuery | 운행 뷰. 「운행 1건」의 정의 |
| `08_view_login.sql` | BigQuery | 기업별 로그인 요약. 관리자 콘솔 / 앱 분리 |
| `09_view_user.sql` | BigQuery | 기업별 사용자·부서 요약. 사용자 수 4종 |
| `50_run_log.sql` | BigQuery | 실행 기록 테이블 |
| `90_check.sql` | BigQuery | 점검. 아무것도 바꾸지 않는다 |

## 데이터 흐름

```
MySQL ──00──▶ parquet ──▶ gs://cartax-biz_cartax_statistics/<테이블>/dt=YYYY-MM-DD/
                                          │
                                       01 외부 테이블
                                          │
                                       03 일 증분 MERGE
                                          ▼
                                       02 raw_* (네이티브)
                                          │
                             04 / 05 / 06 뷰 ──▶ 대시보드·분석
```

## 원천 테이블 대응

| 설계안 | MySQL | 순위 | 비고 |
|---|---|---|---|
| `trip` | `drivingLog` + `deleteDrivingLog` | 1 | 2,500만 행. 60컬럼 중 28개만 |
| `payment` | `payment` + `paySchedule` | 1 | 실패는 `paySchedule.status='E'` 에만 있다 |
| 현재 결제 상태 | `companyPayState` (+`History`) | 1 | 설계안의 「현재 상태 15개」를 통째로 대체 |
| 체험 | `freeExperienceHistory` | 1 | |
| `company` | `company` | 2 | 사업자등록번호·업종·가입경로·GA clientId |
| `user_history` | `user` | 1 | uid → 기업 대응. 사용자 확산 측정의 기준 |
| 부서 | `department` | 2 | `drivingLog.departmentSeq` 해석 |
| 관리자 로그인 | `loginBrowserHistory` | 1 | 비즈 관리자 페이지. 성공·실패·referer |
| 앱 로그인 | `userLoginHistory` | 1 | 기기·OS·앱 버전. `has_app_login` |
| `vehicle_history` | `car` | 3 | 이탈 선행지표 아님이 실증됨. 나중에 |
| `cancel_reason` | **없음** | 1 | 아래 참조 |
| `user_history` | **없음** | 3 | 아래 참조 |

## 원천을 받아 확인된 것 — 설계안이 바뀌는 부분

**① 결제 실패 구분이 이미 되어 있다.**
설계안에서 `fail_type`(renewal/manual)을 새로 만들어 달라고 했고,
「마지막 계약 종료일 = 결제 실패일이 같은지」로 추론하려 했다. 그럴 필요가 없다.

```
payment.contractType   OFFICIAL 정식전환 · UPGRADE 업그레이드 · CHANGE 요금제 변경
                       AGAIN 정기결제 재신청 · RENEW 기간 갱신
                       SCHEDULE 정기결제(예약) · RETRY 결제 재시도
paySchedule.status     R예약 / Y완료 / C취소 / E에러
paySchedule.errorMsg   결제 실패 사유
```

갱신(SCHEDULE·RENEW·RETRY·AGAIN)과 능동 확장(UPGRADE·CHANGE·addCar·add)이
원천에서 이미 갈라진다. `04_view_payment.sql` 의 `attempt_type` 이 이것이다.

**② 현재 상태를 따로 요청할 필요가 없다.**
`companyPayState` 가 기업당 1행으로 현재 계약·자동결제·라이선스·체험 상태를 다 갖고 있다.
`freeCancelDate`(무료체험 중 구독 취소일)까지 있어 이탈 선행지표가 하나 늘었다.

**③ 소급 분석이 가능하다.**
`companyPayStateHistory` 가 상태 변경 이력을 `targetSeq` 로 연결해 갖고 있다.
「10년간 안 쌓아서 소급이 안 된다」가 아니다. `first_payment_*` / `last_payment_*`
같은 요약 컬럼을 따로 받을 이유가 사라졌다.

**④ 사업자등록번호가 이미 있다.** `company.corporateNumber`.
요청할 항목이 아니라 받으면 되는 항목이었다. 다만 특정 시점 이후 가입 건만 있어
회사명 정규화를 없애지는 못한다. 확보율은 `90_check.sql` 5번으로 확인한다.

**⑤ GA4 연결 고리가 있다.** `company.gid` 가 구글애널리틱스 clientId다.
GA4의 `user_pseudo_id` 와 이어지면 마케팅 유입 → 가입이 한 줄로 연결된다.
설계안 10-② 에서 「가장 큰 구멍」이라고 쓴 것의 일부가 메워진다.
(가입 이후 제품 내 행동은 여전히 백지다. 그건 그대로 남는 과제다.)

**⑥ 카택스 케어가 별도 상품이다.** `paySchedule.type = 'cartaxCare'`.
매출 분석에서 요금제(`pricePlan`)와 분리해야 한다.

**⑦ 로그인 이력이 두 벌 있고, 성격이 다르다.** (2026-09-12 추가)

`loginBrowserHistory` 는 **비즈 관리자 페이지 로그인**이다. `cid` 가 관리자 계정
id(`company.cid`)다. 일반 사용자 로그인이 아니다.
`userLoginHistory` 는 앱 로그인이고 주체가 직원(`user.uid`)이다.
**둘을 합쳐 세면 안 된다.** 관리자만 들어오는 회사와 직원까지 앱을 쓰는 회사가
갈리는데, 그게 도입이 확산됐는지의 가장 직접적인 신호다.

설계안 05번에서 「받아야 한다」고 쓴 `pc_first_login_date` / `pc_last_login_date` /
`admin_login_count_total` / `has_app_login` 이 전부 계산된다. 받을 필요가 없다.
그 이상으로 원천에만 있는 것이 둘이다.

- **로그인 실패** — `loginBrowserHistory.success` + `errorMsg`.
  반복 실패 기업은 제품이 불만인 게 아니라 들어오질 못하고 있다. 이탈 원인이 갈린다.
- **유입 경로** — `loginBrowserHistory.referer`.
- **기기·OS·앱 버전** — `userLoginHistory` 가 로그인마다 남긴다. 버전 채택 추적.

주의할 점이 둘 있다.
`userLoginHistory` 에는 **`updateTime` 이 없다.** append-only 라 증분 기준이
`createTime` 이다. 다른 테이블과 다르다.
그리고 **`companySeq` 가 없다.** `uid` 뿐이라 기업에 붙이려면 user 테이블이 필요하다.
`07_view_login.sql` 은 임시로 운행 기록(`userUid` + `companySeq`)으로 잇는데,
운행을 한 번도 안 한 사용자가 빠진다. user 테이블을 받으면 그 CTE 를 갈아끼운다.

## 원천에 없어서 확인이 필요한 것

| 무엇 | 왜 필요한가 | 상태 |
|---|---|---|
| **탈퇴·자동결제 해지 사유** | 설계안 1순위. 다른 어디서도 만들 수 없는 유일한 질적 데이터 | **552컬럼 전수 검색했으나 없다.** 아래 참조 |
| **`role` 테이블** | 관리자 여부 판정. `user.roleSeq` 의 의미 | 시트에 없다. 아래 참조 |
| **`duty` 테이블** | `user.dutySeq`(직책) 의 해석 | 시트에 없다 |

### 해지·탈퇴 사유를 552컬럼에서 찾은 결과

이름과 주석 전체를 `사유 / 해지 / 취소 / 탈퇴 / reason / cancel` 로 훑었다.
**사유 텍스트나 선택지 코드가 들어가는 컬럼은 하나도 없다.** 날짜와 상태만 있다.

| 있는 것 | 무엇 |
|---|---|
| `companyPayState.freeCancelDate` | 무료체험 중 구독 취소한 **날짜** |
| `payment.state = 'Cancel'` | 결제 취소 **상태** |
| `paySchedule.status = 'C'` | 예약 취소 **상태** |
| `paySchedule.errorMsg` | **결제 실패** 사유 — 해지 사유가 아니다 |
| `loginBrowserHistory.errorMsg` | **로그인 실패** 사유 |

후보가 하나 있다. `payment.memo` (text, 주석 없음). 자유 입력이라 무엇을 담는지
모른다. 값을 확인해 볼 가치는 있다. 그 외에는 **별도 테이블일 수밖에 없다.**

### 관리자 여부를 아직 판정할 수 없다

`user.roleSeq` 가 권한 컬럼이지만 **`role` 테이블이 없어 값의 의미를 모른다.**
지금 판단 가능한 것은 행동 기준 하나뿐이다 — **비즈 관리자 페이지에 로그인했다면
관리자다.** `08_view_login.sql` 의 `login_admin` 쪽이 그것이다.

`90_check.sql` 13번이 `role_seq` 분포와 관리자 로그인 여부의 상관을 본다.
특정 값이 관리자 로그인과 강하게 붙으면 그것이 관리자 권한이다. 그래도 추정이라,
`role` 테이블을 받는 편이 낫다.

### 탈퇴 판정 — 대리지표를 쓰지 않는다

`company.enabled` enum('Y','N','X') 에 **X = 탈퇴**가 명시돼 있다.
90일 스냅샷에서 `user_count = 0` 을 대리지표로 쓴 것은 그 원본에 탈퇴 컬럼이
없었기 때문이다. 이제 직접 신호가 있으므로 대리지표를 쓰지 않는다.

다만 **N(미사용)이 무엇인지 모른다.** 관리자 정지인지, 결제 만료 강등인지.
X 와 N 을 묶으면 안 된다. `90_check.sql` 8번으로 셋의 활동 흔적을 비교한다.

## 확정되지 않은 것

- **`company.enabled = 'N'`(미사용)의 정체.** X(탈퇴)와 묶으면 안 된다. `90_check.sql` 8번.
- **`uid` 커버리지.** `raw_user` 에 없는 uid 가 로그인·운행에 나타나면 그 활동이
  어느 기업에도 안 붙는다. `90_check.sql` 11번이 0 이어야 한다.
- **`user_count` 의 정의.** 전체 / 승인 / 미승인 / 탈퇴가 다 다른 숫자다.
  기존 `signup_90days` 의 `user_count` 가 어느 것인지 대조해야 한다. `90_check.sql` 14번.
- **`user.roleSeq`** 의 의미. `role` 테이블이 없다. `90_check.sql` 13번.
- **로그인 이력 규모.** 앱 로그인이 앱 실행마다 남으면 운행보다 클 수도 있다.
  파티션·클러스터 판단이 달라진다. `90_check.sql` 10번.
- **`loginBrowserHistory.parent`** varchar(45), 주석 없음. 의미 미확인이라 뺐다.
- **`payment.type`** 샘플이 전부 `'SC0999'`. 의미 미확인.
- **`createTime` 신뢰 구간.** `payment` seq 1~10 의 `createTime` 이 전부
  `2017-05-15 19:48:10` 인데 `beginDate` 는 2016년이다. 그 시점에 데이터를 이관한
  흔적이다. 이전 행의 `createTime` 은 생성 시각이 아니다. `90_check.sql` 7번.
- **`06_view_trip.sql` 의 판정 3가지.** 합치기 자식 제외 / 동승자 REJECT 제외 /
  GPS 실운행. 스키마 주석만 보고 세웠고 **실제 데이터로 검증되지 않았다.**
  최초 적재 직후 `90_check.sql` 1~3번으로 확인하고 어긋나면 뷰를 고친다.
- **백필 범위.** 10년인가 3년인가. 설계안 10-①.

## 수집하지 않는 것

개인정보는 원천에 있어도 가져오지 않는다. 추출 쿼리 주석에 테이블별로 적어 두었다.

| 대상 | 처리 |
|---|---|
| 인증 정보 (`password`, `ikey`, `autoLoginKey`) | 제외 |
| 개인 성명 (`adminName`, `invoiceeCEOName`, `drivingLog.name`, `dutyName`) | 제외 |
| 연락처 (`tel`, `phone`) | 제외 |
| 이메일 | 도메인만 (`SUBSTRING_INDEX(email,'@',-1)`) |
| 회사 주소 | 시/도 + 시/군/구 2어절까지만 |
| 운행 주소·좌표 (`startAddress`, `stopAddress`, 위경도 4개) | 제외 |
| 자유 입력 (`bigo`, `adminMemo`, `cartaxMemo`, `car.memo`) | 제외 |
| 차량번호 (`car.number`, `user.carNumber`) | 제외 (준식별자) |
| 사용자 성명 (`user.name`) | 제외 |
| 푸시 토큰 (`user.pushId`) | 제외 |
| 사용자 이메일 (`user.email`) | 도메인만 (포털/회사 도메인 구분용) |
| 워크플레이스 로그인 아이디 (`user.wp_login_id`) | 제외. 연동 여부(BOOL)만 |
| 로그인 IP (`loginBrowserHistory.clientIp`) | 제외 (암호화돼 있어도 쓸 분석이 없다) |
| userAgent raw (`loginBrowserHistory.userAgent`) | 제외 (platform/browser/version 으로 파싱돼 있다) |

`loginBrowserHistory.referer` 는 가져온다. 유입 경로 분석에 직결되기 때문이다.
다만 URL 쿼리 파라미터에 이메일·토큰이 실려 올 수 있다. `90_check.sql` 9번으로
확인하고, 섞여 있으면 호스트만 남기도록 바꾼다.

예외가 하나 있다. `paySchedule.errorMsg`(결제 실패 사유)는 자유 텍스트인데 가져온다.
결제 실패의 유일한 기록이기 때문이다. PG 응답 메시지로 보이지만 확인되지 않았다.
최초 적재 후 `90_check.sql` 6번으로 실제 값을 보고, 개인정보가 섞이면
`policy/30_data.md` 에 기준을 세운 뒤 마스킹한다.

## 배포 순서

설계안 11번을 따른다.

1. `signup_90days` 의 월별 집계를 뷰에서 테이블로 (새 데이터 들어오기 전에)
2. `50_run_log.sql` → `02_raw_table.sql` → `01_ext_table.sql` → `04_udf.sql`
3. `user` + `department` + `payment` 계열 + 로그인 이력 적재.
   `user` 를 먼저 넣는다 — uid → 기업 대응이 다른 모든 집계의 전제다
4. `90_check.sql` 로 판정 검증 → 뷰 수정
5. `trip` 최초 전량 (연도별 분할, 회당 약 477 MB)
6. 증분 적재 시작. 90일 스냅샷과 병행
7. 같은 날짜에서 두 경로 대조 **최소 2주**
8. 기존 적재 중단 (테이블은 보존 — 전체 수집 이전 구간의 유일한 기록이다)
