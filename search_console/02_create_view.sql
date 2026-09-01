/* =========================
   [미배포 초안] 2026-09-01 확인

   이 파일은 전체가 주석(/* ... */)으로 감싸여 있다. 실행해도 아무 일도 일어나지 않는다.
   BigQuery의 `carbiz-6f7fc.searchconsole` 데이터셋에는 원본 export 테이블
   (searchdata_url_impression 등)만 있고 아래 v_* 뷰는 하나도 존재하지 않는다.

   쓰려면 주석을 풀고 실행해야 한다. 그 전까지는 초안으로 본다.
========================= */

/*
-- ============================================================
-- cartax.biz Search Console BigQuery View 정의
-- RAW 소스: carbiz-6f7fc.searchconsole.searchdata_url_impression
--   컬럼: data_date, query, url, country, device,
--          clicks, impressions, sum_position
--
-- 핵심 원칙:
--   query dimension 포함 시 클릭/노출 과소집계 발생
--   → 정확한 수치는 query를 제외하고 집계해야 함
--   → avg_position = SAFE_DIVIDE(sum_position, impressions)
-- ============================================================


-- ============================================================
-- VIEW 1. 페이지 기준 일별 집계
--   (searchdata_page_impression 과 동일한 구조)
--   → SC 공식 UI와 동일한 클릭/노출 수치 기반
-- ============================================================
CREATE OR REPLACE VIEW `carbiz-6f7fc.searchconsole.v_page_daily` AS
SELECT
    data_date,
    url,
    country,
    device,
    SUM(clicks)                                         AS clicks,
    SUM(impressions)                                    AS impressions,
    SAFE_DIVIDE(SUM(clicks), SUM(impressions))          AS ctr,
    SAFE_DIVIDE(SUM(sum_position), SUM(impressions))    AS avg_position
FROM `carbiz-6f7fc.searchconsole.searchdata_url_impression`
GROUP BY 1, 2, 3, 4;


-- ============================================================
-- VIEW 3. 월별 요약
-- ============================================================
CREATE OR REPLACE VIEW `carbiz-6f7fc.searchconsole.v_monthly_summary` AS
SELECT
    FORMAT_DATE('%Y-%m', data_date)                     AS ym,
    SUM(clicks)                                         AS clicks,
    SUM(impressions)                                    AS impressions,
    SAFE_DIVIDE(SUM(clicks), SUM(impressions))          AS ctr,
    SAFE_DIVIDE(SUM(sum_position), SUM(impressions))    AS avg_position_weighted
FROM `carbiz-6f7fc.searchconsole.searchdata_url_impression`
GROUP BY 1
ORDER BY 1;


-- ============================================================
-- VIEW 6. YoY 비교 (월 기준)
-- ============================================================
CREATE OR REPLACE VIEW `carbiz-6f7fc.searchconsole.v_yoy_monthly` AS
WITH base AS (
    SELECT
        FORMAT_DATE('%Y-%m', data_date)             AS ym,
        EXTRACT(YEAR  FROM data_date)               AS yr,
        EXTRACT(MONTH FROM data_date)               AS mo,
        SUM(clicks)                                 AS clicks,
        SUM(impressions)                            AS impressions,
        SAFE_DIVIDE(SUM(clicks), SUM(impressions))  AS ctr
    FROM `carbiz-6f7fc.searchconsole.searchdata_url_impression`
    GROUP BY 1, 2, 3
)
SELECT
    curr.ym,
    curr.yr,
    curr.mo,
    curr.clicks                                             AS clicks,
    prev.clicks                                             AS clicks_prev_year,
    SAFE_DIVIDE(curr.clicks - prev.clicks, prev.clicks)    AS clicks_yoy,
    curr.impressions                                        AS impressions,
    prev.impressions                                        AS impressions_prev_year,
    SAFE_DIVIDE(curr.impressions - prev.impressions,
                prev.impressions)                           AS impressions_yoy,
    curr.ctr                                                AS ctr,
    prev.ctr                                                AS ctr_prev_year,
    curr.ctr - prev.ctr                                     AS ctr_delta
FROM base AS curr
LEFT JOIN base AS prev
    ON curr.mo = prev.mo AND curr.yr = prev.yr + 1
ORDER BY curr.ym;

*/
