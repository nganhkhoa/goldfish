#!/usr/bin/env python3
"""Generate compact, exhaustive layout/component families for the inline picker."""
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
records = json.loads((ROOT / "static/character-index.json").read_text())["characters"]
GROUPS = {"⺼":"月", "氵":"水", "扌":"手", "忄":"心", "⺗":"心", "讠":"言", "纟":"糸", "钅":"金", "饣":"食", "犭":"犬", "礻":"示", "衤":"衣", "灬":"火", "亻":"人", "入":"人", "刂":"刀", "阝":"邑", "⻌":"辶"}
BASE = {
 "leftRight": [("People & body", "人 女 月 目 耳 子"), ("Water & weather", "水 冫 雨 气 风"), ("Plants & ground", "木 艹 土 石 禾 米"), ("Hands & tools", "手 刀 力 金 车 弓"), ("Speech & thought", "言 心 口 见 页"), ("Movement", "辶 足 彳 走 攵"), ("Animals", "犬 马 虫 鱼 鸟 牛"), ("Clothes & objects", "糸 衣 食 贝 巾 舟"), ("Places & shapes", "邑 山 田 王 门 广")],
 "topBottom": [("Covers", "宀 冖 穴 艹 雨 ⺮"), ("Marks & tops", "一 亠 ⺍ ⺈ 小 丷"), ("Nature", "日 山 土 田 禾 竹"), ("People & forms", "人 十 大 立 八 羊")],
 "surround": [("Frames & doors", "囗 门 冂 凵 匚 匸"), ("Shelters", "广 尸 厂 疒 户 虍"), ("Movement & open sides", "辶 廴 走 勹 几")],
 "threePart": [("Common forms", "亠 口 辛 ⺍ 王 人 彳 手 八 弓")],
 "overlay": [("Lines & openings", "一 冂 十 口 曰"), ("People & objects", "行 衣 王 禾 刀"), ("Small forms", "丿 丷 七 千 二")],
}
def leader(x): return GROUPS.get(x, x)
def elm_string(x): return '"' + x.replace('"', '\\"') + '"'
def elm_list(xs): return '[ ' + ', '.join(elm_string(x) for x in xs) + ' ]'

by_layout = defaultdict(list)
for r in records: by_layout[r['layout']].append(r)
all_families = {}
for layout, rows in by_layout.items():
    available = list(dict.fromkeys(leader(r['parts'][0]) for r in rows))
    used, result = set(), []
    for name, raw in BASE.get(layout, []):
        parts = [p for p in raw.split() if p in available and p not in used]
        if parts: result.append((name, parts)); used.update(parts)
    missing = [p for p in available if p not in used]
    for start in range(0, len(missing), 9):
        result.append(("More shapes " + str(start // 9 + 1), missing[start:start + 9]))
    all_families[layout] = result

lines = ['module Components.InlinePickerFamilies exposing (familiesFor)', '', 'familiesFor : String -> List ( String, List String )', 'familiesFor layout =', '    case layout of']
for layout, fs in all_families.items():
    lines.append('        ' + elm_string(layout) + ' ->')
    lines.append('            [ ' + '\n            , '.join('( ' + elm_string(name) + ', ' + elm_list(parts) + ' )' for name, parts in fs) + '\n            ]')
lines += ['        _ ->', '            []', '']
(ROOT / 'src/Components/InlinePickerFamilies.elm').write_text('\n'.join(lines))
print('Generated families:', {k: len(v) for k, v in all_families.items()})
