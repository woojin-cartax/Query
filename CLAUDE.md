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

<!-- TODO -->

## 변경 시 할 일

- `HISTORY.md` 맨 위에 항목 추가
- 정책에 영향 주는 변경이면 `_DataAnalytics/HISTORY.md`에도 한 줄 + 이 커밋 해시
