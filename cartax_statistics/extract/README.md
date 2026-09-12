# extract — MySQL 원천 → GCS 적재기

`00_mysql_extract.sql` 의 SELECT 문을 **그대로 읽어서** 실행하고, 결과를 parquet 으로
만들어 GCS 에 올린다. SQL 을 복제하지 않는다 — 복제본은 동기화되지 않는다.

```
00_mysql_extract.sql  ──▶  extract.py  ──▶  gs://cartax-biz_cartax_statistics/<테이블>/dt=YYYY-MM-DD/
02_raw_table.sql      ──▶      (타입)
```

## 왜 SQL 을 직접 못 돌리나

`00_mysql_extract.sql` 을 MySQL 클라이언트에 그대로 붙이면 세 군데서 걸린다.
이 스크립트가 그 셋을 처리한다.

| | 문제 | 처리 |
|---|---|---|
| 1 | `:from` / `:to` 는 MySQL 문법이 아니다 | 실제 날짜로 치환 |
| 2 | `(enabled = 'X')` 가 **0/1 정수**로 나온다 | parquet 단계에서 `bool` 로 캐스팅. **안 하면 BigQuery 적재가 타입에서 깨진다** |
| 3 | `drivingLog` 2,500만 행을 한 번에 읽으면 메모리가 터진다 | 기본키 기준 20만 행씩. `OFFSET` 은 뒤로 갈수록 느려져 쓰지 않는다 |

## 준비

```bash
pip install pymysql pyarrow google-cloud-storage
```

접속 정보는 환경변수로 받는다. **코드나 파일에 적지 않는다.**

```bash
export MYSQL_HOST=... MYSQL_PORT=3306 MYSQL_USER=... MYSQL_PASSWORD=... MYSQL_DB=...
export GCS_BUCKET=cartax-biz_cartax_statistics      # 기본값이라 생략 가능
gcloud auth application-default login               # GCS 쓰기 권한
```

## 실행

```bash
# 먼저 이것부터 — 접속하지 않고 만들어질 SQL 만 본다
python3 extract.py --dry-run

# 시험 추출. 결제 계열 한 달치
python3 extract.py --tables payment,paySchedule --from 2026-08-01 --to 2026-09-01

# 어제치 증분 (전 테이블). 매일 돌릴 것
python3 extract.py

# 운행 최초 전량 — 연도별로 나눠서
for y in $(seq 2016 2026); do python3 extract.py --tables drivingLog --full --year $y; done
```

`--dt` 를 주지 않으면 GCS 폴더가 **오늘 날짜**가 된다. 데이터의 날짜가 아니라
올린 날짜다. 소급 추출을 어제 폴더에 넣으려면 `--dt 2026-09-11` 처럼 지정한다.

## 순서

```
1. user, department, purpose      ← uid → 기업 대응이 다른 모든 집계의 전제다
2. payment, paySchedule,
   companyPayState(+History),
   freeExperienceHistory          ← 작고, 매출·이탈 분석이 즉시 열린다
3. company, loginBrowserHistory,
   userLoginHistory
4. drivingLog (연도별), deleteDrivingLog
5. car                            ← 3순위. 위가 안정된 뒤
```

## 이 스크립트가 하지 않는 것

- **BigQuery 적재.** GCS 까지만 한다. 그다음은 `03_merge_daily.sql` 예약 쿼리다.
- **재시도.** 중간에 끊기면 그 테이블을 다시 돌린다. 같은 `dt` 폴더에 덮어쓰므로
  중복 적재는 생기지 않는다.
- **삭제 감지.** `deleteDrivingLog` 를 따로 뽑는 것이 그 역할이다.

## 확인된 것

`00_mysql_extract.sql` 이 참조하는 **컬럼 210개를 실제 스키마와 전수 대조했다.
불일치 0건.** (2026-09-12, `docs/DB_list.xlsx` 24개 시트 605컬럼 기준)

다만 대조한 것은 **컬럼 이름의 존재**뿐이다. 값이 기대한 형태인지는 시험 추출로
확인한다. 특히 `payment.type`(샘플 전부 `SC0999`)과 `purpose` 조인 키가 그렇다.
