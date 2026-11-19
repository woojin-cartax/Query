# 주간 8주 콤보: 유입 막대(좌) · 순수 신규 가입 선(우). 이번 주 막대만 진하게.
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm
import os
FD = os.path.expanduser("~/Library/Fonts")
for f in ("Regular", "SemiBold", "Bold"):
    fm.fontManager.addfont(f"{FD}/Pretendard-{f}.otf")
plt.rcParams["font.family"] = "Pretendard"

W = ["9/24", "10/01", "10/08", "10/15", "10/22", "10/29", "11/05", "11/12"]
T = [1251, 1541, 1326, 1383, 1367, 1402, 1157, 1221]
S = [22, 27, 25, 41, 39, 32, 33, 63]
NOTE = "유입: 주간보고 기록 · 가입: BigQuery 스냅샷, 정책 v4로 재집계(11/12 주는 11/18 스냅샷 잠정치) · 두 축 모두 0부터"
out = sys.argv[1]

BAR, BAR_HI, LINE, INK, MUTED, GRID, BG = "#9fc5f4", "#2b7bd8", "#e8643a", "#111111", "#555555", "#e6e6e6", "#fbfbfa"
fig, ax = plt.subplots(figsize=(11, 5), dpi=200)
fig.patch.set_facecolor(BG); ax.set_facecolor(BG)
x = range(len(W))
ax.bar(x, T, width=0.6, color=[BAR] * (len(W) - 1) + [BAR_HI], zorder=2, label="홈페이지 유입 (좌)")
ax.set_ylim(0, 2000); ax.set_yticks(range(0, 2001, 250))
ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{int(v):,}"))
ax.grid(axis="y", color=GRID, zorder=0); ax.set_axisbelow(True)
for i, v in enumerate(T):
    last = i == len(W) - 1
    ax.text(i, 500, f"{v:,}", ha="center", va="center", fontsize=11,
            color="white" if last else INK, fontweight="bold" if last else "normal", zorder=3)
ax.set_xticks(list(x)); ax.set_xticklabels(W, fontsize=11, color=MUTED)
ax.tick_params(axis="y", colors=BAR_HI, labelsize=11, length=0); ax.tick_params(axis="x", length=0)
ax.set_ylabel("홈페이지 유입", color=BAR_HI, fontsize=11)
for s in ("top", "right", "left"): ax.spines[s].set_visible(False)
ax.spines["bottom"].set_color(GRID)

a2 = ax.twinx()
a2.plot(x, S, color=LINE, lw=2, marker="o", ms=7, mfc=LINE, mec="white", mew=1.5, zorder=4, label="회원 가입 (우)")
a2.set_ylim(0, 80)
a2.tick_params(axis="y", colors=LINE, labelsize=11, length=0)
a2.set_ylabel("회원 가입 (순수 신규)", color=LINE, fontsize=11)
for s in a2.spines.values(): s.set_visible(False)
for i, v in enumerate(S):
    a2.annotate(str(v), (i, v), xytext=(0, 11), textcoords="offset points", ha="center", va="bottom",
                fontsize=12, fontweight="bold", color=INK,
                bbox=dict(boxstyle="round,pad=0.25", fc="white", ec="none"), zorder=5)

h1, l1 = ax.get_legend_handles_labels(); h2, l2 = a2.get_legend_handles_labels()
ax.legend(h1 + h2, l1 + l2, loc="upper left", bbox_to_anchor=(0, 1.1), ncol=2, frameon=False, fontsize=11)
fig.suptitle("최근 8주 홈페이지 유입 · 회원 가입", x=0.07, y=0.97, ha="left", fontsize=15, fontweight="bold")
fig.text(0.01, 0.015, NOTE, fontsize=9, color=MUTED)
fig.subplots_adjust(left=0.065, right=0.945, top=0.83, bottom=0.11)
fig.savefig(out, facecolor=BG)
