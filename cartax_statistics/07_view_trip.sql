/* ============================================================================
   06. view_trip — 운행 원본 + 집계 판정
   ----------------------------------------------------------------------------
   「운행 1건」이 무엇인지 여기서 한 번만 정한다. 아래 집계는 물려받기만 한다.

   ※ raw_trip 은 require_partition_filter = TRUE 다.
     이 뷰를 쓸 때 반드시 trip_date 조건을 건다. 전 기간이 필요하면
     WHERE trip_date >= '2016-01-01' 처럼 넓게라도 명시한다.
     실수로 2,500만 행을 전량 스캔하는 것을 막는 장치다.

   ※ 아래 세 판정은 아직 실제 데이터로 검증되지 않았다.
     스키마 주석과 컬럼 기본값만 보고 세운 것이다.
     최초 적재 직후 90_check.sql 로 분포를 확인하고, 어긋나면 여기를 고친다.
       ① 합치기 자식 제외      merge_parent_seq > 0 인 행이 자식이라는 전제
       ② 동승자 REJECT 제외    같은 물리 운행이 운전자 수만큼 행으로 생긴다는 전제
       ③ GPS 실운행 판정       gps_distance > 0 이면 실제 주행이라는 전제
   ========================================================================= */

CREATE OR REPLACE VIEW `carbiz-6f7fc.cartax_statistics.view_trip` AS
SELECT
  t.trip_id,
  t.company_seq,
  t.vehicle_seq,
  t.user_uid,
  t.department_seq,
  t.trip_date,
  t.start_time,
  t.stop_time,
  t.distance,
  t.gps_distance,
  t.connected_car_distance,
  t.driving_time,
  t.purpose_code,
  p.purpose_name,        -- ※ 조인 키 미확정. 아래 주석 참조
  p.purpose_type,
  p.is_general_business, -- 국세청 양식의 일반업무 포함 여부
  t.driving_type,
  t.approval_status,
  t.app_version,
  t.oil_amount,
  t.toll_amount,
  t.etc_amount,

  /* ── 집계 대상인가 ────────────────────────────────────────────────
     같은 물리 운행이 여러 행으로 존재한다. 그대로 세면 부풀려진다.
       합치기 : 부모 1행 + 자식 N행. 자식은 부모에 포함돼 있다
       동승자 : 한 차량에 여러 운전자. OWN 이 실제 운전자, REJECT 는 아니다     */
  (
        NOT t.is_deleted
    AND IFNULL(t.merge_parent_seq, 0) = 0
    AND IFNULL(t.overlap_state, 'NONE') != 'REJECT'
  )                                     AS is_countable,

  /* ── 누가 만들었나 ────────────────────────────────────────────────
     관리자만 쓰는 회사와 직원까지 쓰는 회사는 완전히 다른 고객이다.
     확산 여부가 이탈·확장의 갈림길일 가능성이 높다.                          */
  t.is_admin_created,
  IF(t.is_admin_created, 'admin', 'member')  AS actor,

  /* ── 진짜 운행인가 ────────────────────────────────────────────────
     GPS 거리가 잡혔으면 앱이 실제로 주행을 따라간 것이다.
     0이면 수기 입력이거나 관리자가 나중에 만든 기록이다.                      */
  (IFNULL(t.gps_distance, 0) > 0)       AS is_gps_trip,

  /* ── 자동으로 기록됐나 ────────────────────────────────────────────
     자동 운행은 설정을 마친 뒤에야 동작한다. 아하 모먼트 후보 1순위다.
     drivingType 이 트리거 종류다 — 수동 / 비콘 / 블루투스 / 전원.            */
  t.is_auto_start,
  (t.driving_type IS NOT NULL AND t.driving_type != '수동')
                                        AS has_auto_trigger,

  /* ── 비용을 입력했나 ──────────────────────────────────────────────
     유류비·통행료를 넣는다는 것은 정산까지 쓰고 있다는 뜻이다.
     운행 기록만 하는 회사와 구분된다.                                        */
  (IFNULL(t.oil_amount, 0) + IFNULL(t.toll_amount, 0) + IFNULL(t.etc_amount, 0) > 0)
                                        AS has_cost_entry,

  /* ── 결재 워크플로를 쓰나 ────────────────────────────────────────
     상신 상태가 기본값(Y 승인)에서 벗어나 있으면 승인 절차를 돌리고 있다.     */
  (t.approval_status IN ('N','X'))      AS is_in_approval_flow,

  /* ── 커넥티드카 ──────────────────────────────────────────────────
     제휴 기능 채택 여부. N 이 아니면 차량에서 직접 받아온 기록이다.          */
  (IFNULL(t.connected_car_save, 'N') != 'N') AS is_connected_car,

  t.gps_faked,
  t.is_deleted,
  t.is_merge_parent,
  t.merge_parent_seq,
  t.overlap_state,
  t.created_at,
  t.updated_at
FROM `carbiz-6f7fc.cartax_statistics.raw_trip` t

/* ── 운행목적 이름 붙이기 ──────────────────────────────────────────────
   ★ 조인 키가 아직 확정되지 않았다.
     drivingLog.purpose 가 purpose 테이블의 purposeCode / purposeType /
     purposeName 중 무엇과 붙는지 확인되지 않았다. 지금은 purpose_code 로
     걸어 뒀다. 90_check.sql 16번이 세 후보의 매칭률을 재므로, 결과를 보고
     아래 ON 절의 컬럼을 확정한다. 틀렸으면 purpose_name 이 대부분 NULL 로
     나오므로 조용히 넘어가지는 않는다.

   ★ company_seq 를 반드시 함께 건다.
     운행목적은 기업별 정의다. 코드만으로 조인하면 A사의 코드에 B사의 이름이
     붙는다. 이건 NULL 로도 안 드러나고 그럴듯한 값이 나오기 때문에 더 위험하다.

   purpose_state = 'X'(삭제)인 정의도 남긴다. 과거 운행이 그 목적으로 기록됐고,
   지금 지워졌다고 해서 그때 기록이 없어지는 것은 아니다.                     */
LEFT JOIN `carbiz-6f7fc.cartax_statistics.raw_purpose` p
  ON  t.company_seq  = p.company_seq
  AND t.purpose_code = p.purpose_code;
