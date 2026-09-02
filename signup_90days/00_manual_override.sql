/* =========================
   수동 판정 목록 — 데이터만으로는 가릴 수 없는 판단을 사람이 기록하는 곳.

   자동 판정(테스트 정규식 / 탈퇴 / 중복)은 그대로 돌고, 여기 적은 것이 그 위에 얹힌다.

     test     테스트 계정으로 분류해 제외한다. 정규식이 놓친 계정을 보탠다.
     exclude  테스트는 아니지만 집계에서 빼야 하는 계정.
     keep     중복으로 제외된 계정을 되살린다.

   우선순위
     1. 테스트 (자동 정규식 OR 수동 test)  -> 제외
     2. 탈퇴   (user_count = 0)            -> 제외
     3. 수동 exclude                       -> 제외
     4. 수동 keep                          -> 중복 제외만 되살림
     5. 자동 중복 판정

   keep은 중복 판정만 뒤집는다. 테스트나 탈퇴로 빠진 계정은 keep을 걸어도 돌아오지
   않는다. 실수로 테스트 계정을 통계에 넣는 사고를 막기 위해서다. 정말 되살려야 하면
   그 계정의 test 지정을 지운다.

   ── 항목을 추가하는 방법 ──
   아래 UNNEST 배열에 STRUCT를 한 줄 더 넣고 이 파일을 실행한다.
   뷰를 재배포할 필요는 없다. 뷰가 이 테이블을 조회 시점에 읽는다.
   반드시 reason을 적는다. 근거 없는 수동 판정은 나중에 아무도 못 고친다.
========================= */

CREATE TABLE IF NOT EXISTS `carbiz-6f7fc.signup_90days.manual_override` (
  company_code STRING  NOT NULL,
  override     STRING  NOT NULL,   -- test / exclude / keep
  reason       STRING  NOT NULL,
  decided_on   DATE    NOT NULL,
  decided_by   STRING,
  updated_at   TIMESTAMP
);

MERGE `carbiz-6f7fc.signup_90days.manual_override` T
USING (
  SELECT * FROM UNNEST([
    STRUCT(
      'D1629'      AS company_code,
      'test'       AS override,
      '두림야스카와 사내 테스트용 계정. 체험중이면서 최근 2주 운행 15회라 실사용 예외 규칙에 걸려 살아남지만 실제 고객이 아니다.' AS reason,
      DATE '2026-09-02' AS decided_on,
      'woojin'     AS decided_by
    )
    -- 새 항목은 위 STRUCT를 복사해 아래에 쉼표로 이어 붙인다.
  ])
) S
ON T.company_code = S.company_code
WHEN MATCHED THEN UPDATE SET
  T.override   = S.override,
  T.reason     = S.reason,
  T.decided_on = S.decided_on,
  T.decided_by = S.decided_by,
  T.updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
  INSERT (company_code, override, reason, decided_on, decided_by, updated_at)
  VALUES (S.company_code, S.override, S.reason, S.decided_on, S.decided_by, CURRENT_TIMESTAMP())
WHEN NOT MATCHED BY SOURCE THEN
  /* 파일에서 지운 항목은 테이블에서도 지운다. 파일이 원본이다. */
  DELETE;
