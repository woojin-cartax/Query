import importlib.util, collections, csv, datetime as dt, sys
import os; Q = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "92_weekly_signup.py")
spec = importlib.util.spec_from_file_location("w", Q); w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
usage_path, snap, week, out = sys.argv[1:5]
start = dt.date.fromisoformat(week); end = start + dt.timedelta(days=6)
usage = w.load_usage(usage_path); same, decided = w.load_decisions()
allrows = w.bq(f"""
SELECT company_code AS c, company_name AS n, IFNULL(company_name_norm,'') AS nn, IFNULL(corporate_number_norm,'') AS corp,
       is_test_account AS t, FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', signup_date) AS s,
       IFNULL(vehicle_count,0) AS vc, IFNULL(plan_detail,'') AS pl, IFNULL(pricing_plan,'') AS pp,
       IFNULL(signup_device,'') AS dev
FROM `{w.PROJECT}.signup_statistics.view_signup_statistics`
WHERE snapshot_date = '{snap}' AND signup_date IS NOT NULL""")
is_test = lambda r: r["t"] not in (False, "false") or r["c"] in w.MANUAL_TEST
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
members = collections.defaultdict(list); by_name = collections.defaultdict(list)
for r in rows:
    members[g.find(r["c"])].append(r)
    if r["nn"]: by_name[r["nn"]].append(r)
inw = lambda r: start <= dt.date.fromisoformat(r["s"][:10]) <= end
targets = [r for r in rows if inw(r)]
pairs, review = [], []
for r in targets:
    pd = (dt.date.fromisoformat(r["s"][:10]) - dt.timedelta(days=1)).isoformat()
    for p in members[g.find(r["c"])]:
        if p["s"] < r["s"]: pairs.append((r["c"], p["c"], pd))
    for p in by_name.get(r["nn"], []) if r["nn"] else []:
        if p["s"] < r["s"] and g.find(p["c"]) != g.find(r["c"]) and not (p["corp"] and r["corp"]) and frozenset((r["c"], p["c"])) not in decided:
            review.append((r, p))
prev = collections.defaultdict(list)
if pairs:
    st = ",".join(f"STRUCT('{n}' AS nc, '{p}' AS pc, DATE '{d}' AS pd)" for n, p, d in pairs)
    lo = min(d for _, _, d in pairs)
    for q in w.bq(f"""SELECT x.nc, x.pc, IFNULL(v.plan_detail,'') AS pl,
 IFNULL(FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', v.last_trip_date_start),'') AS lt,
 IFNULL(FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', v.pc_last_login_date),'') AS ll
FROM UNNEST([{st}]) x LEFT JOIN `{w.PROJECT}.signup_statistics.view_signup_statistics` v
 ON v.company_code = x.pc AND v.snapshot_date = x.pd AND v.snapshot_date BETWEEN '{lo}' AND '{snap}'"""):
        prev[q["nc"]].append(q)
def classify(r):
    ps = prev.get(r["c"])
    if not ps: return "신규", []
    gaps, paid, codes = [], False, []
    for q in ps:
        p = by_code[q["pc"]]
        last = max([p["s"]] + [v for v in (q["lt"], q["ll"]) if v and v < r["s"]])
        gaps.append((dt.date.fromisoformat(r["s"][:10]) - dt.date.fromisoformat(last[:10])).days)
        paid |= q["pl"] in w.PAID; codes.append((p["s"], q["pc"]))
    codes = [c for _, c in sorted(codes, reverse=True)]
    return ("중복" if paid or min(gaps) < w.GAP_DAYS else "재가입"), codes
cnt = collections.Counter()
with open(out, "w", encoding="utf-8-sig", newline="") as f:
    wr = csv.writer(f)
    wr.writerow(["company_code","회사명","가입일시","v4_분류","이전_계정_코드","차량수","요금제","가입경로_구분","테스트_제외"])
    for r in sorted([r for r in allrows if inw(r)], key=lambda r: r["s"]):
        dev = "APP" if r["dev"].startswith(("AOS","iOS")) else "PC/모바일"
        if is_test(r):
            wr.writerow([r["c"], r["n"], r["s"].replace("T"," "), "테스트", "", r["vc"], r["pl"] or r["pp"], dev, "Y"]); cnt["테스트"] += 1; continue
        k, codes = classify(r); cnt[k] += 1
        wr.writerow([r["c"], r["n"], r["s"].replace("T"," "), k, " ".join(codes), r["vc"], r["pl"] or r["pp"], dev, ""])
print(dict(cnt), "rows", sum(cnt.values()))
print("판정 요청", len(review))
for r, p in review:
    print(f"  {r['c']} {r['n']} (사업자번호 {'있음' if r['corp'] else '없음'}, 가입 {r['s'][:10]})  ~  {p['c']} {p['n']} (사업자번호 {'있음' if p['corp'] else '없음'}, 가입 {p['s'][:10]})")
