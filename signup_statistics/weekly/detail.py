import importlib.util, csv, datetime as dt, sys
import os; Q = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "92_weekly_signup.py")
spec = importlib.util.spec_from_file_location("w", Q); w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
src, snap = sys.argv[1:3]
R = [r for r in csv.DictReader(open(src, encoding="utf-8-sig")) if r["v4_분류"] in ("재가입", "중복")]
pairs = [(r["company_code"], p, (dt.date.fromisoformat(r["가입일시"][:10]) - dt.timedelta(days=1)).isoformat(), r) for r in R for p in r["이전_계정_코드"].split()]
st = ",".join(f"STRUCT('{n}' AS nc, '{p}' AS pc, DATE '{d}' AS pd)" for n, p, d, _ in pairs)
lo = min(d for *_, d, _ in [(a, b, c, r) for a, b, c, r in pairs])
res = {(q["nc"], q["pc"]): q for q in w.bq(f"""SELECT x.nc, x.pc, IFNULL(v.plan_detail,'') AS pl, IFNULL(v.trip_count_total,0) AS tc,
 FORMAT_DATETIME('%Y-%m-%d', v.signup_date) AS ps,
 IFNULL(FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', v.last_trip_date_start),'') AS lt,
 IFNULL(FORMAT_DATETIME('%Y-%m-%dT%H:%M:%S', v.pc_last_login_date),'') AS ll
FROM UNNEST([{st}]) x LEFT JOIN `{w.PROJECT}.signup_statistics.view_signup_statistics` v
 ON v.company_code = x.pc AND v.snapshot_date = x.pd AND v.snapshot_date BETWEEN '{lo}' AND '{snap}'""")}
codes = ",".join(sorted({f"'{p}'" for _, p, _, _ in pairs}))
cur = {q["c"]: q["ps"] for q in w.bq(f"""SELECT company_code AS c, FORMAT_DATETIME('%Y-%m-%d', signup_date) AS ps
FROM `{w.PROJECT}.signup_statistics.view_signup_statistics` WHERE snapshot_date = '{snap}' AND company_code IN ({codes})""")}
for n, p, d, r in pairs:
    q = res[(n, p)]
    if not q["ps"]: q["ps"] = cur[p]
    s = r["가입일시"].replace(" ", "T")
    last = max([q["ps"]] + [v for v in (q["lt"], q["ll"]) if v and v < s])
    gap = (dt.date.fromisoformat(s[:10]) - dt.date.fromisoformat(last[:10])).days
    print("|".join([r["v4_분류"], n, r["회사명"], p + (" (유료)" if q["pl"] in w.PAID else ""), f"{int(q['tc']):,}", q["ps"], f"{gap:,}일"]))
