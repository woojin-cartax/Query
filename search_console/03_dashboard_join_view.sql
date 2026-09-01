/* =========================
   [미배포 초안] 2026-09-01 확인

   이 파일은 전체가 주석(/* ... */)으로 감싸여 있다. 실행해도 아무 일도 일어나지 않는다.
   BigQuery의 `carbiz-6f7fc.searchconsole` 데이터셋에는 원본 export 테이블
   (searchdata_url_impression 등)만 있고 아래 v_* 뷰는 하나도 존재하지 않는다.

   쓰려면 주석을 풀고 실행해야 한다. 그 전까지는 초안으로 본다.
========================= */

/*
CREATE OR REPLACE VIEW `carbiz-6f7fc.searchconsole.v_dashboard_main` AS
SELECT
  p.data_date,
  FORMAT_DATE('%Y-%m', p.data_date)          AS ym,
  p.url,
  p.country,
  p.device,
  p.clicks,
  p.impressions,
  p.ctr,
  p.avg_position,

  -- 전년동기 데이터 JOIN
  y.clicks_prev_year,
  y.impressions_prev_year,
  y.clicks_yoy,
  y.impressions_yoy,
  y.ctr_prev_year,
  y.ctr_delta

FROM `carbiz-6f7fc.searchconsole.v_page_daily` p
LEFT JOIN `carbiz-6f7fc.searchconsole.v_yoy_monthly` y
  ON FORMAT_DATE('%Y-%m', p.data_date) = y.ym
  */