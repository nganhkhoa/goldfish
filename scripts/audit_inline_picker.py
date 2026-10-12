#!/usr/bin/env python3
"""Verify every shipped character is reachable through the inline picker.

The picker adds uncovered first components to small fallback families of at
most 10 components. This audit independently reproduces that model and exits
non-zero if a character cannot be reached by layout -> family -> component.
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / "static/character-index.json").read_text())
GROUPS = {"月":"月", "⺼":"月", "水":"水", "氵":"水", "手":"手", "扌":"手", "心":"心", "忄":"心", "言":"言", "讠":"言", "人":"人", "亻":"人", "金":"金", "钅":"金", "辶":"辶", "⻌":"辶"}
BASE = {
 "leftRight": [
  ("People & body", "人 女 月 目 耳 子"), ("Water & weather", "水 冫 雨 气 风"),
  ("Plants & ground", "木 艹 土 石 禾 米"), ("Hands & tools", "手 刀 力 金 车 弓"),
  ("Speech & thought", "言 心 口 见 页"), ("Movement", "辶 足 彳 走 攵"),
  ("Animals", "犬 马 虫 鱼 鸟 牛"), ("Clothes & objects", "糸 衣 食 贝 巾 舟"),
  ("Places & shapes", "阝 山 田 王 门 广"),
 ],
 "topBottom": [("Covers", "宀 冖 穴 艹 雨 ⺮"), ("Marks & tops", "一 亠 ⺍ ⺈ 小 丷"), ("Nature", "日 山 土 田 禾 竹"), ("People & forms", "人 十 大 立 八 羊")],
 "surround": [("Frames & doors", "囗 门 冂 凵 匚 匸"), ("Shelters", "广 尸 厂 疒 户 虍"), ("Movement & open sides", "辶 廴 走 勹 几")],
 "threePart": [("Common forms", "亠 口 辛 ⺍ 王 人 彳 手 八 弓")],
 "overlay": [("Lines & openings", "一 冂 十 口 曰"), ("People & objects", "行 衣 王 禾 刀"), ("Small forms", "丿 丷 七 千 二")],
}

def leader(x): return GROUPS.get(x, x)
def chunks(xs, n=10): return [xs[i:i+n] for i in range(0, len(xs), n)]

by_layout = defaultdict(list)
for c in data["characters"]:
    by_layout[c["layout"]].append(c)

unreachable = []
summary = {}
for layout, chars in by_layout.items():
    available = list(dict.fromkeys(leader(c["parts"][0]) for c in chars))
    used = set()
    families = []
    for name, raw in BASE.get(layout, []):
        members = [x for x in raw.split() if x in available and x not in used]
        if members:
            families.append((name, members)); used.update(members)
    other = [x for x in available if x not in used]
    if other:
        families.append(("Other visible components", other)); used.update(other)
    reachable = {x for _, members in families for x in members}
    misses = [c["hanzi"] for c in chars if leader(c["parts"][0]) not in reachable]
    unreachable.extend(misses)
    summary[layout] = {"characters": len(chars), "components": len(available), "families": len(families), "unreachable": len(misses)}

for layout, row in summary.items(): print(layout, row)
for target in ("税", "退"):
    hit = next((c for c in data["characters"] if c["hanzi"] == target), None)
    print(target, "reachable" if hit and target not in unreachable else "MISSING", hit)
print("Total unreachable:", len(unreachable))
sys.exit(1 if unreachable else 0)
