import importlib.util, collections, csv, datetime as dt, sys
import os; Q = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "92_weekly_signup.py")
spec = importlib.util.spec_from_file_location("w", Q); w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
usage_path, out = sys.argv[1:3]; crm_paths = sys.argv[3:]  # CRM-PAYMENT export (선택)
SNAP, STAT0, R90_0 = "2026-11-18", "2026-09-15", "2026-01-26"
W0 = dt.date(2026, 1, 1); END = dt.date(2026, 11, 18)
WEEKS = [W0 + dt.timedelta(days=7 * i) for i in range((END - W0).days // 7 + 1)]
wk = lambda d: W0 + dt.timedelta(days=7 * ((d - W0).days // 7))
D = dt.date.fromisoformat
tb = lambda v: v in (True, "true")

# ---- v4 분류 (92 로직)
usage = w.load_usage(usage_path); same, decided = w.load_decisions()
allrows = w.bq(f"""
SELECT company_code AS c, IFNULL(company_name_norm,'') AS nn, IFNULL(corporate_number_norm,'') AS corp,
       is_test_account AS t, FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', signup_date) AS s, IFNULL(vehicle_count,0) AS vc
FROM `{w.PROJECT}.signup_statistics.view_signup_statistics`
WHERE snapshot_date = '{SNAP}' AND signup_date IS NOT NULL""")
is_test = lambda r: r["t"] not in (False, "false") or r["c"] in w.MANUAL_TEST
test_codes = {r["c"] for r in allrows if is_test(r)}
rows = [r for r in allrows if not is_test(r)]
by_code = {r["c"]: r for r in rows}
g = w.Groups(by_code); keyed = collections.defaultdict(list)
for r in rows:
    if r["corp"]: keyed[("corp", r["corp"])].append(r["c"])
    lid = usage.get(r["c"], {}).get("id", "")
    if r["nn"] and lid: keyed[("name_id", r["nn"], lid)].append(r["c"])
for codes in keyed.values():
    for c in codes[1:]: g.union(codes[0], c)
for x, y in same: g.union(x, y)
members = collections.defaultdict(list)
for r in rows: members[g.find(r["c"])].append(r)
targets = [r for r in rows if W0 <= D(r["s"][:10]) <= END]
pairs = []
for r in targets:
    pd = max((D(r["s"][:10]) - dt.timedelta(days=1)).isoformat(), STAT0)  # 스냅샷 시작 전은 9/15 상태로 대용
    pairs += [(r["c"], p["c"], pd) for p in members[g.find(r["c"])] if p["s"] < r["s"]]
prev = collections.defaultdict(list)
for i in range(0, len(pairs), 400):
    st = ",".join(f"STRUCT('{n}' AS nc, '{p}' AS pc, DATE '{d}' AS pd)" for n, p, d in pairs[i:i + 400])
    for q in w.bq(f"""SELECT x.nc, x.pc, IFNULL(v.plan_detail,'') AS pl,
 IFNULL(FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', v.last_trip_date_start),'') AS lt,
 IFNULL(FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', v.pc_last_login_date),'') AS ll
FROM UNNEST([{st}]) x LEFT JOIN `{w.PROJECT}.signup_statistics.view_signup_statistics` v
 ON v.company_code = x.pc AND v.snapshot_date = x.pd AND v.snapshot_date BETWEEN '{STAT0}' AND '{SNAP}'"""):
        prev[q["nc"]].append(q)
def classify(r):
    ps = prev.get(r["c"])
    if not ps: return "신규"
    gaps, paid = [], False
    for q in ps:
        p = by_code[q["pc"]]
        last = max([p["s"]] + [v for v in (q["lt"], q["ll"]) if v and v < r["s"]])
        gaps.append((D(r["s"][:10]) - D(last[:10])).days); paid |= q["pl"] in w.PAID
    return "중복" if paid or min(gaps) < w.GAP_DAYS else "재가입"
kind = {r["c"]: classify(r) for r in targets}
new = {r["c"]: (D(r["s"][:10]), int(r["vc"])) for r in targets if kind[r["c"]] == "신규"}

# ---- 신규결제, 가입 90일 내 계정 (signup_90days, 1/26~)
snaps = w.bq(f"""
SELECT FORMAT_DATE('%Y-%m-%d', snapshot_date) AS d, company_code AS c,
       UPPER(IFNULL(pricing_plan,'')) IN ('PLUS','PREMIUM') AND NOT IFNULL(is_trial_active, FALSE) AS paid,
       -- 원천 이상일용 추정: 체험 = 가입일 포함 14일, 14일 안 유료 전환은 계좌이체뿐 (정상일 일치율 99.9%)
       UPPER(IFNULL(pricing_plan,'')) = 'PLUS' OR (UPPER(IFNULL(pricing_plan,'')) = 'PREMIUM'
         AND (STARTS_WITH(IFNULL(contract_type,''),'계좌') OR DATE_DIFF(snapshot_date, DATE(signup_date), DAY) + 1 >= 15)) AS paid_est,
       STARTS_WITH(IFNULL(contract_type,''),'계좌') AND DATE_DIFF(snapshot_date, DATE(signup_date), DAY) + 1 <= 2 AS instant_bank,
       IFNULL(vehicle_count, 0) AS vc
FROM `{w.PROJECT}.signup_90days.raw_signup_90days`
WHERE snapshot_date BETWEEN '{R90_0}' AND '{SNAP}'""")
SKIP = {"2026-07-29"}  # 요금제 값까지 하루 깨짐(FREE→PLUS→FREE) — 버린다
BAD = {f"2026-07-{d:02d}" for d in range(1, 22)} | {"2026-06-30"}  # is_trial_active 전 계정 false — 원천 이상, 추정값으로 대체
hist = collections.defaultdict(list)
for s in snaps:
    if s["c"] not in test_codes and s["d"] not in SKIP:
        pa = tb(s["paid_est"]) if s["d"] in BAD else tb(s["paid"])
        hist[s["c"]].append((s["d"], pa, int(s["vc"]), tb(s["instant_bank"])))
paid90, nw90, seen = {}, {}, set()
for c, h in hist.items():
    h.sort(); pp = None
    for d, pa, vc, ib in h:
        if pa and c not in seen and (pp is False or (pp is None and d > R90_0)):
            # 가입 1~2일차에 이미 계좌 PLUS — 네이버웍스 연동 가입(가입=플러스). 결제 전환이 아니다
            (nw90 if pp is None and ib else paid90)[c] = (D(d), vc)
        if pa: seen.add(c)
        pp = pa

# ---- 전 계정 신규결제 · 업셀 (signup_statistics, 9/15~)
ex = ",".join(f"'{c}'" for c in w.MANUAL_TEST)
stat = w.bq(f"""
WITH s0 AS (
  SELECT snapshot_date AS d, company_code AS c, IFNULL(plan_detail,'') IN ('plus','premium') AS paid,
         IFNULL(vehicle_count,0) AS vc, IFNULL(is_test_account, FALSE) AS t
  FROM `{w.PROJECT}.signup_statistics.view_signup_statistics`
  WHERE snapshot_date BETWEEN '{STAT0}' AND '{SNAP}'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY snapshot_date, company_code ORDER BY data_collection_time DESC) = 1
), s AS (
  SELECT *, LAG(paid) OVER x AS paid0, LAG(vc) OVER x AS vc0, LAG(d) OVER x AS d0
  FROM s0 WINDOW x AS (PARTITION BY c ORDER BY d)
)
SELECT FORMAT_DATE('%Y-%m-%d', d) AS d, c, vc, paid AND NOT paid0 AS newpaid,
       IF(paid AND paid0, vc - vc0, 0) AS dv
FROM s
WHERE d0 = DATE_SUB(d, INTERVAL 1 DAY) AND NOT t AND c NOT IN ({ex})
  AND ((paid AND NOT paid0) OR (paid AND paid0 AND vc != vc0))""")
paid_all, up = {}, collections.defaultdict(lambda: [0, 0, set()])
for q in sorted(stat, key=lambda q: q["d"]):
    d = D(q["d"])
    if tb(q["newpaid"]):
        paid_all.setdefault(q["c"], (d, int(q["vc"])))
    elif int(q["dv"]) > 0:
        u = up[wk(d)]; u[0] += int(q["dv"]); u[2].add(q["c"])
    else:
        up[wk(d)][1] += -int(q["dv"])

# ---- CRM-PAYMENT export 가 덮는 주는 CRM 이 원천 (crm_payments.py 참고)
crm_weeks = set()
if crm_paths:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import crm_payments as cp
    days, crm = cp.load(crm_paths, test_codes); crm_weeks = cp.covered_weeks(days, wk)
    sig = {c: D(r["s"][:10]) for c, r in by_code.items()}
    paid_all = cp.override(paid_all, crm, crm_weeks, wk, lambda c, d: c in sig)
    paid90 = cp.override(paid90, crm, crm_weeks, wk, lambda c, d: c in sig and (d - sig[c]).days + 1 <= 90)
STAT_W = dt.date(2026, 9, 17); R90_W = dt.date(2026, 1, 29)
with open(out, "w", encoding="utf-8-sig", newline="") as f:
    wr = csv.writer(f)
    wr.writerow(["주_시작(목)", "주_끝(수)", "신규가입_기업수", "신규가입_차량수",
                 "신규결제_90일내계정_기업수", "신규결제_90일내계정_차량수", "네이버웍스형_즉시플러스_기업수",
                 "신규결제_전계정_기업수", "신규결제_전계정_차량수",
                 "업셀_증가_기업수", "업셀_증가_차량", "감소_차량", "비고"])
    for W in WEEKS:
        nw = [v for c, (d, v) in new.items() if wk(d) == W]
        row = [W, W + dt.timedelta(days=6), len(nw), sum(nw)]
        note = []
        if W >= R90_W:
            p = [v for d, v in paid90.values() if wk(d) == W]
            row += [len(p), sum(p), sum(1 for d, _ in nw90.values() if wk(d) == W)]
        else:
            row += ["", "", ""]; note.append("90일내 결제: 원천 1/26 시작 — 1/29주부터")
        if W >= STAT_W:
            p = [v for d, v in paid_all.values() if wk(d) == W]; u = up[W]
            row += [len(p), sum(p), len(u[2]), u[0], u[1]]
        else:
            row += ["", "", "", "", ""]
            if W >= R90_W: note.append("전계정 결제·업셀: 9/17주부터")
        if W in crm_weeks: note.append("결제: CRM-PAYMENT 기준")
        if W < dt.date(2026, 9, 10): note.append("v4 이전계정 상태 9/15 대용")
        if dt.date(2026, 6, 25) <= W <= dt.date(2026, 7, 23): note.append("원천 이상 6/30~7/21·7/29 — 결제 상태 추정(가입 14일 규칙)")
        row.append(" · ".join(note)); wr.writerow(row)
print("v4", collections.Counter(kind.values()), "pairs", len(pairs), "stat rows", len(stat))
