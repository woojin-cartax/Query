SELECT *
--FROM `carbiz-6f7fc.signup_90days.ext_signup_90days` 
--FROM `carbiz-6f7fc.signup_90days.raw_signup_90days` 
--FROM `carbiz-6f7fc.signup_90days.view_signup_90days` 
FROM `carbiz-6f7fc.signup_90days.view_signup_90days_latest` 

/* latest 테이블은 기업별 최신 1개의 Row만 가져옴 */
--WHERE dt = "2026-02-04"
--WHERE DATE(signup_date) = '2026-03-30'
--WHERE snapshot_date = "2026-01-25"
--WHERE sequence_id = "20076"
--WHERE is_booking_date is not null 
--WHERE company_code = "H1235"
--WHERE signup_date = "2026-03-29"
--LIMIT 100

