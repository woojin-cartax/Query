import importlib.util, collections, csv, datetime as dt, statistics, sys
import os; Q = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "92_weekly_signup.py")
spec = importlib.util.spec_from_file_location("w", Q); w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
usage_path, out_dir = sys.argv[1:3]; crm_paths = sys.argv[3:]  # CRM-PAYMENT export (선택)
SNAP, FIRST_SNAP = "2026-11-18", "2026-09-15"
W0 = dt.date(2026, 8, 27); END = dt.date(2026, 11, 18)
WEEKS = [W0 + dt.timedelta(days=7 * i) for i in range(12)]
wk = lambda d: W0 + dt.timedelta(days=7 * ((d - W0).days // 7))
D = dt.date.fromisoformat

# ---- v4 분류 (92 와 같은 로직, 12주)
usage = w.load_usage(usage_path); same, decided = w.load_decisions()
allrows = w.bq(f"""
SELECT company_code AS c, IFNULL(company_name_norm,'') AS nn, IFNULL(corporate_number_norm,'') AS corp,
       is_test_account AS t, FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', signup_date) AS s
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
pairs, proxied = [], set()
for r in targets:
    pd = (D(r["s"][:10]) - dt.timedelta(days=1)).isoformat()
    if pd < FIRST_SNAP: pd = FIRST_SNAP  # 스냅샷 시작 전 — 9/15 상태로 대신 본다
    for p in members[g.find(r["c"])]:
        if p["s"] < r["s"]:
            pairs.append((r["c"], p["c"], pd))
            if pd == FIRST_SNAP: proxied.add(r["c"])
prev = collections.defaultdict(list)
for i in range(0, len(pairs), 400):
    st = ",".join(f"STRUCT('{n}' AS nc, '{p}' AS pc, DATE '{d}' AS pd)" for n, p, d in pairs[i:i + 400])
    for q in w.bq(f"""SELECT x.nc, x.pc, IFNULL(v.plan_detail,'') AS pl,
 IFNULL(FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', v.last_trip_date_start),'') AS lt,
 IFNULL(FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', v.pc_last_login_date),'') AS ll
FROM UNNEST([{st}]) x LEFT JOIN `{w.PROJECT}.signup_statistics.view_signup_statistics` v
 ON v.company_code = x.pc AND v.snapshot_date = x.pd AND v.snapshot_date BETWEEN '{FIRST_SNAP}' AND '{SNAP}'"""):
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
new = {r["c"]: D(r["s"][:10]) for r in targets if kind[r["c"]] == "신규"}

# ---- 체험·결제 전환 (signup_90days 일별 스냅샷, 가입 90일 내 계정)
snaps = w.bq(f"""
SELECT FORMAT_DATE('%Y-%m-%d', snapshot_date) AS d, company_code AS c,
       IFNULL(is_trial_active, FALSE) AS tr,
       UPPER(IFNULL(pricing_plan,'')) IN ('PLUS','PREMIUM') AND NOT IFNULL(is_trial_active, FALSE) AS paid,
       UPPER(IFNULL(pricing_plan,'')) = 'PLUS' OR (UPPER(IFNULL(pricing_plan,'')) = 'PREMIUM'
         AND (STARTS_WITH(IFNULL(contract_type,''),'계좌') OR DATE_DIFF(snapshot_date, DATE(signup_date), DAY) + 1 >= 15)) AS paid_est,
       STARTS_WITH(IFNULL(contract_type,''),'계좌') AND DATE_DIFF(snapshot_date, DATE(signup_date), DAY) + 1 <= 2 AS instant_bank,
       IFNULL(vehicle_count, 0) AS vc
FROM `{w.PROJECT}.signup_90days.raw_signup_90days`
WHERE snapshot_date BETWEEN '2026-07-25' AND '{SNAP}'""")
tb = lambda v: v in (True, "true")
SKIP = {"2026-07-29"}  # 요금제 값까지 하루 깨짐(FREE→PLUS→FREE) — 버린다
BAD = {f"2026-07-{d:02d}" for d in range(1, 22)} | {"2026-06-30"}  # is_trial_active 전 계정 false — 원천 이상
hist = collections.defaultdict(list)
for s in snaps:
    if s["c"] not in test_codes and s["d"] not in SKIP:
        bad_day = s["d"] in BAD  # 체험은 이상일 앞뒤로 이어 보고, 결제는 추정값
        hist[s["c"]].append((s["d"], None if bad_day else tb(s["tr"]), tb(s["paid_est"]) if bad_day else tb(s["paid"]), int(s["vc"]), tb(s["instant_bank"])))
trial, paid, st, sp = {}, {}, set(), set()   # code -> (첫 전환일, 차량수)
for c, h in hist.items():
    h.sort(); pt, pp = None, None
    for d, tr, pa, vc, ib in h:
        # 첫 관측에서 이미 켜져 있으면 관측 시작(7/25) 이후 첫 등장일 때만 전환으로 본다 — 가입 직후 등장
        first_ok = d > "2026-07-25"
        if tr and c not in st and (pt is False or (pt is None and first_ok)): trial[c] = (D(d), vc)
        if pa and c not in sp and (pp is False or (pp is None and first_ok)) and not (pp is None and ib): paid[c] = (D(d), vc)
        if tr: st.add(c)
        if pa: sp.add(c)
        if tr is not None: pt = tr
        pp = pa

# ---- CRM-PAYMENT export 가 덮는 주는 CRM 이 원천 (crm_payments.py 참고)
crm_weeks = set()
if crm_paths:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import crm_payments as cp
    days, crm = cp.load(crm_paths, test_codes); crm_weeks = cp.covered_weeks(days, wk)
    sig = {c: D(r["s"][:10]) for c, r in by_code.items()}
    paid = cp.override(paid, crm, crm_weeks, wk, lambda c, d: c in sig and (d - sig[c]).days + 1 <= 90)

# ---- 1) 주간 퍼널
with open(f"{out_dir}/weekly_funnel_12w.csv", "w", encoding="utf-8-sig", newline="") as f:
    wr = csv.writer(f)
    wr.writerow(["주_시작(목)", "주_끝(수)", "신규가입_기업수", "신규가입_차량수",
                 "체험시작_기업수", "체험시작_차량수", "신규결제_기업수", "신규결제_차량수",
                 "체험시작_중_결제전환_기업수(10/28까지)", "체험→결제_전환율", "비고"])
    vc_now = {s["c"]: int(s["vc"]) for s in snaps if s["d"] == SNAP}
    for W in WEEKS:
        e = W + dt.timedelta(days=6)
        nw = [c for c, d in new.items() if wk(d) == W]
        tw = [c for c, (d, _) in trial.items() if wk(d) == W]
        pw = [c for c, (d, _) in paid.items() if wk(d) == W]
        conv = [c for c in tw if c in paid and paid[c][0] >= trial[c][0]]
        note = []
        if any(c in proxied for c in nw): note.append("v4 이전계정 상태 9/15 스냅샷 대용")
        if (END - W).days < 21: note.append("전환율 미성숙 — 주 마지막 가입이 15일차 미도달")
        if W in crm_weeks: note.append("결제: CRM-PAYMENT 기준")
        wr.writerow([W, e, len(nw), sum(vc_now.get(c, 0) for c in nw),
                     len(tw), sum(trial[c][1] for c in tw), len(pw), sum(paid[c][1] for c in pw),
                     len(conv), f"{len(conv) / len(tw):.1%}" if tw else "", " · ".join(note)])

# ---- 2) 가입 코호트 (v4 신규)
with open(f"{out_dir}/signup_cohort_12w.csv", "w", encoding="utf-8-sig", newline="") as f:
    wr = csv.writer(f)
    hdr = ["가입주_시작(목)", "가입_기업수", "가입_차량수"]
    for n in (7, 14, 28, 56): hdr += [f"{n}일내_결제_기업수", f"{n}일내_결제_차량수"]
    hdr += ["결제_기업수(10/28까지)", "가입→결제_소요일_중앙값", "비고"]
    wr.writerow(hdr)
    for W in WEEKS:
        cs = [c for c, d in new.items() if wk(d) == W]
        row = [W, len(cs), sum(vc_now.get(c, 0) for c in cs)]
        imm = []
        for n in (7, 14, 28, 56):
            if W + dt.timedelta(days=6 + n) > END:
                row += ["", ""]; imm.append(f"{n}일")
                continue
            hit = [c for c in cs if c in paid and 0 <= (paid[c][0] - new[c]).days <= n]
            row += [len(hit), sum(paid[c][1] for c in hit)]
        lag = [(paid[c][0] - new[c]).days for c in cs if c in paid and paid[c][0] >= new[c]]
        row += [len(lag), statistics.median(lag) if lag else ""]
        row.append(("미도달: " + "·".join(imm)) if imm else "")
        wr.writerow(row)

print("v4", collections.Counter(kind.values()), "proxied", len(proxied))
for W in WEEKS:
    print(W, "신규", sum(1 for d in new.values() if wk(d) == W))
