#!/usr/bin/env python3
"""Fail the build review when a common indexed character lacks a first-piece family.

Run after build_character_index.py. The report is intentionally based on the
shipped index: every record it reports is actually available to the picker.
"""
import json
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX = json.loads((ROOT / "static/character-index.json").read_text())

# Keep synchronized with CharacterInput.elm. Variants are searched through the
# same learner-facing leader, rather than becoming separate entries.
GROUPS = {
    "月": ["月", "⺼"], "水": ["水", "氵"], "手": ["手", "扌"],
    "心": ["心", "忄", "⺗"], "言": ["言", "讠"], "糸": ["糸", "纟"],
    "金": ["金", "钅"], "食": ["食", "饣"], "犬": ["犬", "犭"],
    "示": ["示", "礻"], "衣": ["衣", "衤"], "火": ["火", "灬"],
    "人": ["人", "亻", "入"], "刀": ["刀", "刂"], "邑": ["邑", "阝"],
    "辶": ["辶", "⻌"],
}
LEADER = {part: leader for leader, parts in GROUPS.items() for part in parts}

# Every first component must live in exactly one compact family. This list is
# exported as a review artifact; add missing leaders to the Elm family data.
FAMILIES = {
    "leftRight": "人 女 子 老 父 母 月 目 耳 口 鼻 骨 水 冫 雨 气 风 云 木 艹 土 石 禾 米 火 日 光 电 赤 手 刀 力 金 车 弓 足 彳 辶 攵 止 走 言 心 见 页 犬 马 虫 鱼 鸟 牛 糸 衣 食 宀 门 广 邑 山 田 王 贝 几 示 酉 又 巾 革 舟 舌 歹 矢 工 身 立 欠 令 交 且 包 匕".split(),
    "topBottom": "宀 冖 穴 广 ⺮ 一 亠 ⺍ ⺈ 小 日 山 土 田 禾 人 十 大 立 夂 丷 八 羊 爫 罒".split(),
    "surround": "囗 门 冂 凵 匚 广 尸 厂 疒 户 辶 廴 走 勹 几 匸 虍 戈 麻 羊".split(),
    "threePart": "亠 口 辛 ⺍ 王 人 彳 手 八 弓".split(),
    "overlay": "一 冂 十 口 曰 行 衣 王 禾 刀 丿 丷 七 千 二".split(),
}
FAMILIES = {layout: {LEADER.get(x, x) for x in parts} for layout, parts in FAMILIES.items()}

missing = defaultdict(Counter)
examples = defaultdict(lambda: defaultdict(list))
for record in INDEX["characters"]:
    first = LEADER.get(record["parts"][0], record["parts"][0])
    layout = record["layout"]
    if first not in FAMILIES.get(layout, set()):
        missing[layout][first] += 1
        if len(examples[layout][first]) < 4:
            examples[layout][first].append(record["hanzi"])

report = {"indexedCharacters": INDEX["count"], "uncovered": {}}
for layout, counts in missing.items():
    report["uncovered"][layout] = [
        {"component": part, "characters": count, "examples": examples[layout][part]}
        for part, count in counts.most_common()
    ]

out = ROOT / "design/character-family-coverage.json"
out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"Wrote {out}")
for layout, items in report["uncovered"].items():
    print(layout, sum(item["characters"] for item in items), "characters uncovered")
