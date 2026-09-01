# query — 작업 규칙

상위 `_DataAnalytics/CLAUDE.md`와 `_DataAnalytics/policy/`가 **자동으로 적용된다.**
충돌하면 상위 정책이 이긴다. 여기에는 이 작업장에만 해당하는 것만 쓴다.

## 이 작업장

BigQuery 쿼리 관리. 데이터셋 단위 SQL 폴더

## 여기서 커밋한다

이 폴더는 **독립 저장소**다. 작업 결과는 여기에 커밋하고
상위 `_DataAnalytics` 저장소에는 절대 커밋하지 않는다.

```bash
git rev-parse --show-toplevel   # 지금 어느 저장소인지 확인
```

## 작업장 고유 규칙

### SSOT는 로컬이다

BigQuery 콘솔의 저장된 쿼리·예약 쿼리가 아니라 **이 저장소의 SQL 파일이 원본**이다.

- 콘솔에서 직접 고치지 않는다. 여기서 고치고 콘솔에 반영한다.
- 콘솔에만 있는 쿼리를 발견하면 반입한다. 대응표는 `README.md`의 파일 구조 표에 있다.
- 예약 쿼리(`update_daily`)는 파일을 고쳐도 자동 반영되지 않는다.
  콘솔에서 별도로 수정해야 하며, 어긋남 확인 방법은 `README.md`에 적어뒀다.

### BigQuery 실행 원칙 — 기본은 "실행하지 않는다"

이 작업장의 산출물은 **SQL 파일**이다. BigQuery에 반영하는 것은 사람이 콘솔에서 한다.
에이전트가 `bq`로 직접 실행하는 것은 예외이며, 아래 규칙을 따른다.

**승인 없이 해도 되는 것 — 읽지도 바꾸지도 않는 것만**

```bash
bq query --use_legacy_sql=false --dry_run < <파일>   # 문법·타입·참조 검사, 비용 0원
bq show / bq ls                                      # 스키마·목록 조회
```

**매번 사전 승인 — 무엇을 왜 실행하는지 먼저 말하고 허락받는다**

- 데이터를 읽는 모든 쿼리 (`SELECT` 실행, 값 확인, 건수 세기) — 스캔 비용이 발생한다
- 되돌릴 수 없는 모든 것: `DROP` / `CREATE OR REPLACE TABLE` / `MERGE` /
  `INSERT` / `UPDATE` / `DELETE` / `TRUNCATE`
- `bq rm` / `bq mk` / `bq load` / `bq cp`

**절대 하지 않는 것**

- `signup_90days/02_raw_table_생성.sql`, `signup_90days/80_year_merge.sql`을
  통째로 실행. 선두에 `DROP TABLE`이 있어 raw 누적 스냅샷이 전량 삭제된다.
  복구는 GCS 원본으로부터 전량 재머지뿐이다.
- 사용자가 "실행해줘"라고만 한 것을 확대 해석해 여러 파일을 연달아 실행

### dry-run의 한계

dry-run은 **컴파일 체크지 런타임 검증이 아니다.**

- 잡는 것: 문법, 존재하지 않는 테이블·컬럼, 타입 불일치, 스캔 바이트 추정
- 못 잡는 것: 값이 맞는지, 로직이 의도대로인지
- `DECLARE`로 시작하는 멀티 스테이트먼트 스크립트(`03_merge_update.sql`)는
  검사가 얕다. 단일 `CREATE VIEW`(04~07)는 제대로 잡힌다.

dry-run 통과를 "검증 완료"라고 말하지 않는다. 통과했다는 사실만 그대로 보고한다.

## 변경 시 할 일

- `HISTORY.md` 맨 위에 항목 추가
- 정책에 영향 주는 변경이면 `_DataAnalytics/HISTORY.md`에도 한 줄 + 이 커밋 해시
