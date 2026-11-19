"""CRM-PAYMENT export 를 신규결제의 원천으로 쓴다.

스냅샷(요금제 값 변화)으로 잡은 신규결제는 두 가지로 틀린다.
- 이미 유료인 계정이 하루 무료로 찍혔다 돌아오면 신규결제로 잡힌다 (11/12주 N649·H738)
- 계약 시작일이 미래인 가상계좌 결제는 요금제가 아직 안 바뀌어 빠진다 (11/12주 B1029)
CRM export 가 덮는 주(목~수)는 스냅샷 결과를 버리고 CRM 행으로 바꾼다.

제외: 상태≠Complete, 신규≠Y, 결제수단 FREE 또는 결제금액 0 (관리자 개설 체험),
회사명에 '테스트' (테스트·교육 계정), 테스트 계정 코드.
"""
import csv, datetime as dt

D = dt.date.fromisoformat


def load(paths, test_codes=()):
    rows = []
    for p in paths:
        with open(p, encoding="utf-8-sig") as f:
            rows += list(csv.DictReader(f))
    days = [D(r["결제일"]) for r in rows]
    paid = {}
    for r in sorted(rows, key=lambda r: (r["결제일"], r["결제시각"])):
        if r["상태"] != "Complete" or r["신규"] != "Y": continue
        if r["결제수단"] == "FREE" or int(r["결제금액"] or 0) == 0: continue
        if "테스트" in r["회사명"] or r["ikey"] in test_codes: continue
        paid.setdefault(r["ikey"], (D(r["결제일"]), int(r["차량 수"] or 0)))
    return days, paid


def covered_weeks(days, wk):
    """CRM 행이 있는 주(목~수) 전체를 CRM 이 덮는다고 본다 — export 는 주 단위로 받는다."""
    return {wk(d) for d in days}


def override(snap_paid, crm_paid, weeks, wk, keep=lambda c, d: True):
    """덮는 주의 스냅샷 결제를 지우고 CRM 결제를 넣는다. keep 으로 대상 계정을 거른다(90일내 등)."""
    out = {c: v for c, v in snap_paid.items() if wk(v[0]) not in weeks}
    for c, (d, vc) in crm_paid.items():
        if wk(d) in weeks and keep(c, d):
            out.setdefault(c, (d, vc))
    return out
