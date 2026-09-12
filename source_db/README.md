# source_db — 서비스 MySQL 원천 사본

전체 고객사 데이터를 원천에 가까운 형태로 받아 BigQuery에 쌓는다.
집계는 받지 않고 우리가 만든다. 기준이 바뀌어도 데이터를 다시 받지 않기 위해서다.

설계 근거는 「일별 스냅샷 설계안 (2판)」에 있다.
현재 운영 중인 90일 스냅샷(`../signup_90days/`)은 **끄지 않는다.** 당분간 병행한다.

## 상태

**아직 아무것도 배포되지 않았다.** MySQL 추출이 시작되기 전의 초안이다.
데이터셋 `source_db`, 버킷 `gs://cartax-biz_source_db/` 도 아직 만들지 않았다.
이름은 확정 전이라 바꿀 수 있다.

## 파일

| 파일 | 어디서 실행하나 | 무엇을 하나 |
|---|---|---|
| `00_mysql_extract.sql` | **서비스 MySQL** (개발팀) | 원천 추출. 우리는 실행하지 않는다 |
| `01_ext_table.sql` | BigQuery | GCS parquet을 가리키는 외부 테이블 |
| `02_raw_table.sql` | BigQuery | 네이티브 테이블. **선두가 DROP이라 통째 실행 금지** |
| `03_merge_daily.sql` | BigQuery 예약 쿼리 | 일 증분 MERGE |
| `04_view_payment.sql` | BigQuery | 결제 사실 뷰. 성공·실패·환불·시도 성격 판정 |
| `05_view_company.sql` | BigQuery | 기업 마스터 + 현재 결제 상태 |
| `06_view_trip.sql` | BigQuery | 운행 뷰. 「운행 1건」의 정의 |
| `50_run_log.sql` | BigQuery | 실행 기록 테이블 |
| `90_check.sql` | BigQuery | 점검. 아무것도 바꾸지 않는다 |

## 데이터 흐름

```
MySQL ──00──▶ parquet ──▶ gs://cartax-biz_source_db/<테이블>/dt=YYYY-MM-DD/
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

## 원천에 없어서 확인이 필요한 것

| 무엇 | 왜 필요한가 | 상태 |
|---|---|---|
| **탈퇴·자동결제 해지 사유** | 설계안 1순위. 다른 어디서도 만들 수 없는 유일한 질적 데이터 | 받은 시트에 없다. 별도 테이블인지 확인 필요 |
| **사용자(user) 테이블** | `user_count`, 로그인 이력, 확산 분석 | 시트에 없다. `drivingSetting.userUid` 로 존재는 확인됨 |
| **로그인 이력** | `pc_login_count_total`, `has_app_login` | `company.lastLogin` 은 단일 값. 이력 테이블이 따로 있는지 |
| **부서(department)** | `departmentSeq` 의 해석 | 시트에 없다 |

## 확정되지 않은 것

- **`plan_level` 숫자 ↔ 요금제 이름.** 샘플에서 1·2·3 이 관찰됐으나 대응이 확인되지 않았다.
  기존 `signup_90days` 의 FREE/PLUS/PREMIUM 과 맞춰야 한다. `90_check.sql` 4번.
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
| 차량번호 (`car.number`) | 제외 (준식별자) |

예외가 하나 있다. `paySchedule.errorMsg`(결제 실패 사유)는 자유 텍스트인데 가져온다.
결제 실패의 유일한 기록이기 때문이다. PG 응답 메시지로 보이지만 확인되지 않았다.
최초 적재 후 `90_check.sql` 6번으로 실제 값을 보고, 개인정보가 섞이면
`policy/30_data.md` 에 기준을 세운 뒤 마스킹한다.

## 배포 순서

설계안 11번을 따른다.

1. `signup_90days` 의 월별 집계를 뷰에서 테이블로 (새 데이터 들어오기 전에)
2. `50_run_log.sql` → `02_raw_table.sql` → `01_ext_table.sql`
3. `payment` 계열부터 적재. 작고 매출·이탈 분석이 즉시 열린다
4. `90_check.sql` 로 판정 검증 → 뷰 수정
5. `trip` 최초 전량 (연도별 분할, 회당 약 477 MB)
6. 증분 적재 시작. 90일 스냅샷과 병행
7. 같은 날짜에서 두 경로 대조 **최소 2주**
8. 기존 적재 중단 (테이블은 보존 — 전체 수집 이전 구간의 유일한 기록이다)
