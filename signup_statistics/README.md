# signup_statistics — 전 고객사 일별 집계 스냅샷

`signup_90days` 를 전 고객사로 넓힌 것이다. 같은 모양, 넓은 모집단.

## 상태

**배포 전.** 데이터셋 `signup_statistics` 를 아직 만들지 않았다.
**원본은 이미 쌓이고 있다** — 2026-09-15 부터 하루도 빠지지 않았다.

```
gs://cartax-biz-statistics/dt=YYYY-MM-DD/YYYYMMDD.parquet
  하루 1파일 · 약 1.9 MB · 37컬럼 · 20,575행 (2026-10-01)
  업로드 22:48 KST · data_collection_time 전 행 동일 22:00:02
```

## 왜 이 폴더가 따로 있나

`cartax_statistics/` 는 **원천 13테이블**을 받는 설계다(운행 1건이 1행, 결제 1건이 1행).
이 폴더는 **집계 스냅샷 1개**를 받는다. 둘은 서로 배타적인 배포이고 합쳐지지 않는다.

그래서 브랜치로 나누지 않고 폴더를 둘로 뒀다. 브랜치는 합쳐지거나 버려질 코드에 쓴다.
데이터셋이 다르므로 **둘을 동시에 적재해 같은 날짜로 대조할 수 있다** —
설계안 11번 전환 순서 7번이 그것이다(최소 2주 대조 후 결정).

| | `cartax_statistics/` | `signup_statistics/` (여기) |
|---|---|---|
| 받는 것 | 원천 13테이블 | 집계 스냅샷 1개 |
| 기준이 바뀌면 | 재계산으로 끝난다 | 다시 요청해야 한다 |
| 시작 조건 | **개발팀이 추출을 만들어야** 한다 | **이미 들어오고 있다** |
| 공유 파일 | — | `04_udf.sql` 정도 |

## 90일 피드와의 차이 — 컬럼 34개 공통, 차이 셋

| | |
|---|---|
| `corporate_number` | **사업자등록번호. 여기만 있다.** 회사명 문자열 추측을 대체한다 |
| `license_type` | 90일에서 `license_count` 로 바로잡은 그 오기. 여기서도 교정한다 |
| `updated_at` 없음 | 증분 기준이 없다. **날짜별 전량**이다 |

`signup_device` 에 `iOS : 앱 다운로드 > 관리자 계정 가입` 처럼 **유입 경로 문장**이
들어온다(일부는 비어 있다). 90일 피드의 `pc/mobile/ios/and` 보다 풍부하다.

## 파일

| 파일 | 어디서 | 역할 |
|---|---|---|
| `01_ext_table.sql` | BigQuery | 외부 테이블. `dt=` 필터 필수 |
| `02_raw_table.sql` | BigQuery | 네이티브 테이블. **선두가 DROP 이라 통째 실행 금지** |
| `03_merge_daily.sql` | 예약 쿼리 | 일별 MERGE + 로그. 소급 템플릿 포함 |
| `04_view_derived.sql` | BigQuery | 파생 컬럼. **판정은 전부 여기서 한 번만** |
| `05_view_dedup.sql` | BigQuery | 중복기업 판정. 사업자번호 1순위 |
| `50_run_log.sql` | BigQuery | 실행 기록. 최초 1회 |

## 적재 방식

MERGE 키가 `(snapshot_date, company_code)` 이고 **그것만으로 멱등하다.**
`updated_at` 이 없어도 되는 이유는 날짜가 파티션이라서다 — 같은 날짜를 다시 받으면
그 날짜를 덮어쓰는 것이 맞다. 「더 새로운 행만 갱신」 비교를 하지 않는다.

소급 적재는 `03_merge_daily.sql` 안의 주석 템플릿으로 한다. 파일을 복제하지 않는다.

## 일정

| | |
|---|---|
| 원본 업로드 | **22:48 KST** (90일 피드는 22:00) |
| 예약 쿼리 | **23:30 KST** = `every day 14:30` (UTC) |
| `target_dt` | `INTERVAL 0 DAY` — **당일 파일을 당일 머지한다** |

`INTERVAL 1 DAY` 로 두면 예약 실행이 영구히 하루씩 뒤처진다. 멱등해서 에러는 안 나고
이미 적재된 날짜를 매일 다시 머지하며 당일 건이 안 들어온다. `signup_90days` 와 같은
규약(`INTERVAL 0`)을 쓴다.

업로드(22:48)와 머지(23:30) 사이 42분 여유다. 90일 피드는 60분(22:00 → 23:00)이다.
업로드가 늦어지면 그날은 `EMPTY` 로 남고 다음 날 같은 날짜를 다시 머지하면 복구된다 —
키가 `(snapshot_date, company_code)` 라 멱등하다.

## corporate_number 가 중복 판정을 바꾼다

이 피드에만 사업자등록번호가 있다. **추측 대신 확정**이 된다.

```
1순위  사업자등록번호     같으면 같은 법인이다. 확정
2순위  정규화 회사명      사업자번호가 없을 때만. 추측
판정 안 함  일반명사       「개인택시」류. 회사를 식별하지 못한다
```

실측 (2026-10-05, 테스트 제외 20,417개사):

| | |
|---|---|
| 사업자번호 보유 | 14,907 (73.0%) |
| 사업자번호 기준 중복 | 2,764 |
| 이름 기준 중복 | 4,573 |
| **이름은 같은데 사업자번호가 다르다** | **464** ← 잘못 묶이고 있었다 |
| **사업자번호는 같은데 이름이 다르다** | **344** ← 이름 판정이 놓치고 있었다 |

앞의 464 가 더 아프다. 묶인 쪽은 중복 제외로 통계에서 사라지는데
**잘못 묶인 것은 눈에 보이지 않는다.** 덜 묶인 것은 나중에 발견된다.

### 「개인택시」 문제

회사명 칸에 업태를 적어 넣은 일반명사가 있다. 이름으로 묶으면 **서로 완전히 다른
사업자가 한 덩어리**가 된다.

```
개인택시   사업자 25곳     개인화물 9   개별화물 3   개인 4   null 3
```

해당 100개사가 11개 이름그룹에 뭉쳐 있고 그중 85개사가 서로 다른 사업자였다.
`is_generic_name` 으로 판정에서 뺀다 — 묶을 근거가 없으면 묶지 않는다.

### 적용 결과

```
판정 키 출처     기업      중복그룹   제외
corp_no        14,907    2,764    1,486
name            5,478      779      398
none              32        0        0

제외 수   사업자번호 우선 1,884  vs  이름만 1,821
```

순제외는 63개사 늘지만 **안에서 양방향 교체가 일어난다.**

| | |
|---|---|
| 되살아남 | **586개사** — 이름으로 잘못 묶여 제외됐던 것 |
| 새로 제외 | **649개사** — 사업자번호가 같아 중복으로 확정된 것 |

`주식회사 레이시온` 3건이 같은 사업자번호다 — 이름 판정은 유료 계정이 있으면 전부
살렸는데 사업자번호로 보면 진짜 중복이다. 반대로 `골프프렌드`·`제이앤드` 는 이름이
같지만 사업자번호가 달라 다른 회사로 확정됐다.

### signup_90days 와의 관계

판정 규칙(`plan_detail`·`company_name_norm`·`is_test_account`·`is_active_free`·
유지 우선순위)은 **글자 그대로 같게 맞췄다.** 두 피드의 같은 지표가 다른 숫자를
내면 안 된다. 한쪽을 고치면 반드시 다른 쪽도 고친다.

다른 점은 사업자번호와 일반명사 판정뿐이다. 90일 피드에는 그 컬럼이 없다.

## 예약 쿼리 — 터미널로 만들었다

```
projects/975350524805/locations/asia-northeast3/transferConfigs/
  6ac3ec57-0000-2b3a-9570-3c286d353572        signup_statistics_daily
```

본문은 `03_merge_daily.sql` 과 **바이트 동일**하다(sha 앞 12자 대조). 갱신은 이렇게 한다 —
SQL 에 백틱이 있어 셸을 거치면 깨지므로 Python 으로 직접 넘긴다.

```python
import json, subprocess, io
CFG = "projects/975350524805/locations/asia-northeast3/transferConfigs/6ac3ec57-0000-2b3a-9570-3c286d353572"
sql = io.open("03_merge_daily.sql", encoding="utf-8").read()
subprocess.run(["bq","update","--transfer_config",
                f"--params={json.dumps({'query': sql})}", CFG], check=True)
```

### ★ 스크립트 쿼리에는 destinationDatasetId 가 비어 있어야 한다

`DECLARE`·`MERGE` 를 쓰는 예약 쿼리에 대상 데이터셋을 지정하면 **매 실행이 실패한다.**

```
Dataset specified in the query ('') is not consistent with Destination dataset 'signup_statistics'.
```

`signup_90days` 의 `update_daily` 도 `destinationDatasetId: ''` 다. 생성할 때
`--target_dataset` 을 **주지 않는다.**

이미 지정해 버렸으면 `bq update --transfer_config --target_dataset=''` 로는 안 지워진다 —
**"successfully updated" 라고 하고도 값이 남는다.** REST 로 비운다.

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -X PATCH "https://bigquerydatatransfer.googleapis.com/v1/${CFG}?updateMask=destinationDatasetId" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"destinationDatasetId": ""}'
```

### 수동 실행은 KST 밤에만 의미가 있다

`bq mk --transfer_run` 으로 즉시 돌리면 `CURRENT_DATE("Asia/Seoul")` 가 그 시점 기준이다.
새벽에 돌리면 **그날 파일이 아직 없어 `EMPTY` 가 정상이다.** 실패가 아니다.
소급이 필요하면 `03_merge_daily.sql` 의 소급 템플릿을 로컬에서 돌린다.

## 주의

- **`02_raw_table.sql` 을 통째로 실행하지 않는다.** 선두 `DROP TABLE` 이 누적 스냅샷을
  전량 삭제한다. 복구는 GCS 원본으로부터 전량 재머지뿐이다.
- **`trip_count_today` 를 일별 추이에 쓰지 않는다.** 수집이 22:00(KST)에 돌아서
  22~24시 운행은 **어느 날의 `trip_count_today` 에도 들어가지 않는다.**
  90일 피드에서 실측한 편차가 **상시 −1.1%** (하루 약 309건)다.
  일별 추이는 `trip_count_total` 차분을 쓴다 — 같은 측정에서 누적 감소 0건이었다.
- **말일 22시 이후 가입은 다음 날 파일로 들어온다.** 월별 집계를 만들 때
  `signup_90days/06_monthly_base.sql` 과 같은 보정이 필요하다(기준일 +1일까지 보되
  그 달에 가입한 기업에만 적용). 안 하면 영구 누락이 생긴다.
- `corporate_number` 는 적재 시 원본 그대로 둔다. 하이픈 표기 정규화는 뷰에서 한다.

## 다음

1. 데이터셋 생성 → `50` → `02` → `01` 순서로 배포
2. 2026-09-15 부터 소급 적재 (20일치)
3. `corporate_number` 확보율 확인 → 중복 판정 개선 검증
4. 뷰 작성. `signup_90days/04~09` 를 참고하되 판정은 한 곳에서만 한다
