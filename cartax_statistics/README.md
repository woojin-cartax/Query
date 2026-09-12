# cartax_statistics — 서비스 MySQL 원천 사본

전체 고객사 데이터를 원천에 가까운 형태로 받아 BigQuery에 쌓는다.
집계는 받지 않고 우리가 만든다. 기준이 바뀌어도 데이터를 다시 받지 않기 위해서다.

설계 근거는 「일별 스냅샷 설계안 (2판)」에 있다.
현재 운영 중인 90일 스냅샷(`../signup_90days/`)은 **끄지 않는다.** 당분간 병행한다.

## 관련 문서

| 문서 | 무엇 | 상태 |
|---|---|---|
| [cartax_statistics 수집 명세](https://claude.ai/code/artifact/c3330e75-097c-441d-b3ec-1ebbcabe725b) | **이 폴더의 운영 기준.** 컬럼 단위로 무엇을 왜 받고 왜 빼는가 | 최신 |
| 일별 스냅샷 설계안 2판 | 왜 이렇게 받기로 했는가. 판단 근거 | 근거는 유효하나 「받아야 할 것」 목록이 낡았다 |
| 가입 데이터 수집 명세 | 현재 운영 중인 90일 스냅샷의 실측 (36컬럼) | 그대로 둔다. 전체 수집 이전의 유일한 기록 |

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
| `04_udf.sql` | BigQuery | 공용 판정. `plan_name()` · `is_super_admin()`. **뷰보다 먼저** |
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
| `user_history` | `user` | 1 | uid → 기업 대응. 42컬럼 중 13개 |
| 부서 | `department` | 2 | 개수와 계층 깊이만. 부서명은 안 받는다 |
| 운행목적 | `purpose` | 2 | `trip.purpose_code` 해석. **기업별 정의다** |
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
| **`role` 테이블** | `role_seq` 의 0 이외 값들이 서로 어떻게 다른지 | 시트에 없다. 관리자/사용자 구분은 됐다 |
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

### 관리자 판정 — 두 기준이 따로 있다

`role_seq = 0` 이 최고관리자다. 나머지는 사용자로 분류한다 (2026-09-12 확인).
판정은 `04_udf.sql` 의 `is_super_admin()` 한 곳에만 둔다.

이것과 **별개로** 행동 기준이 하나 더 있고, 섞으면 안 된다.

| 어디 | 무엇을 재나 | 기준 |
|---|---|---|
| `09_view_user.sql` `user_count_admin` | 권한상 관리자가 몇 명인가 | 명부 (`role_seq`) |
| `08_view_login.sql` `is_admin_only` | 관리자 콘솔에 실제로 들어왔는가 | 행동 (로그인) |

둘이 어긋나는 것 자체가 신호다 — 관리자 권한은 있는데 콘솔에 한 번도 안 들어온
기업은 도입이 시작되지 않은 것이다.

`role` 테이블은 여전히 없다. 0 이외의 값들이 서로 어떻게 다른지는 모르고, 지금
필요한 구분은 관리자/사용자 둘뿐이라 그것만 만들었다. `90_check.sql` 13·13b 가
전제를 검증한다 — `role_seq=0` 이 아닌데 콘솔에 들어오는 사용자가 있거나,
관리자가 0명인 기업이 많으면 전제가 틀린 것이다.

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
- **`role_seq` 의 0 이외 값.** 관리자/사용자 구분은 됐으나 나머지 등급의 의미는
  모른다. `90_check.sql` 13·13b 로 전제만 검증한다.
- **로그인 이력 규모.** 앱 로그인이 앱 실행마다 남으면 운행보다 클 수도 있다.
  파티션·클러스터 판단이 달라진다. `90_check.sql` 10번.
- **`loginBrowserHistory.parent`** varchar(45), 주석 없음. 의미 미확인이라 뺐다.
- **`payment.type`** 샘플이 전부 `'SC0999'`. 의미 미확인.
- **`purpose` 조인 키.** `drivingLog.purpose` 가 `purposeCode` / `purposeType` /
  `purposeName` 중 무엇과 붙는지 미확인. `07_view_trip.sql` 은 일단 `purpose_code`
  로 걸어 뒀다. `90_check.sql` 16번이 세 후보의 매칭률을 재므로 그 결과로 확정한다.
  틀렸으면 `purpose_name` 이 대부분 NULL 로 나와 조용히 넘어가지 않는다.
  **조인에 `company_seq` 를 반드시 함께 건다.** 운행목적은 기업별 정의라 코드만으로
  조인하면 A사 코드에 B사 이름이 붙는다 — NULL 로도 안 드러나고 그럴듯한 값이
  나와서 더 위험하다. 겹침 규모는 `90_check.sql` 16b.
- **`createTime` 신뢰 구간.** `payment` seq 1~10 의 `createTime` 이 전부
  `2017-05-15 19:48:10` 인데 `beginDate` 는 2016년이다. 그 시점에 데이터를 이관한
  흔적이다. 이전 행의 `createTime` 은 생성 시각이 아니다. `90_check.sql` 7번.
- **`06_view_trip.sql` 의 판정 3가지.** 합치기 자식 제외 / 동승자 REJECT 제외 /
  GPS 실운행. 스키마 주석만 보고 세웠고 **실제 데이터로 검증되지 않았다.**
  최초 적재 직후 `90_check.sql` 1~3번으로 확인하고 어긋나면 뷰를 고친다.
- **백필 범위.** 10년인가 3년인가. 설계안 10-①.

## 수집하지 않는 것

개인정보는 원천에 있어도 가져오지 않는다. 그와 별개로, **쓸 분석이 없으면 받지
않는다**(설계안 선별 기준 4). 원천에 남아 있으므로 나중에 받을 수 있다.

| 테이블 | 원본 | 받는 것 | 뺀 이유 |
|---|---|---|---|
| `drivingLog` → `trip` | 60 | 29 | 주소·좌표·성명·메모(개인정보), 안전운전 지표(쓸 분석 없음) |
| `user` | 42 | 13 | 기기·OS·언어·권한 세부·커넥티드카(쓸 분석 없음), 성명·이메일·토큰(개인정보) |
| `department` | 11 | 6 | 부서명(어느 집계에도 안 들어감 + 「홍길동팀」 위험) |
| `company` | 56 | 20 | 인증·성명·연락처·미사용 컬럼, 설정 16개(쓸 분석 없음) |

추출 쿼리 주석에 테이블별로 무엇을 왜 뺐는지 적어 두었다.

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
| 푸시 토큰·기기 ID (`user.pushId`, `user.deviceId`) | 제외 |
| 사용자 이메일 (`user.email`) | 도메인만 (포털/회사 도메인 구분용) |
| 워크플레이스 식별자 (`user.wp_login_id`, `wp_emp_id`) | 제외 |
| 부서명 (`department.name`, `fullName`) | 제외 |

`company` 의 설정은 **둘만 받는다.**

| 컬럼 | 값 | 왜 남겼나 |
|---|---|---|
| `setting_save_map_point` | A전체 / Y출도착 / N선택 / X미저장 / C차량별 | `X` 면 경로가 아예 안 남는다 |
| `setting_privacy_mode` | none / user / car / all | `none` 이 아니면 운행이 가려진다 |

둘 다 **수집되는 데이터의 양 자체**를 정하는 설정이다. 이걸 모르고 「운행이 적다」고
읽으면 사용 부진으로 오진한다. `06_view_company.sql` 의 `has_restricted_logging` 이
그 구분이다. 나머지 16개 설정은 쓸 분석이 없어 뺐다.
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
