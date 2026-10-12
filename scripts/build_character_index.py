#!/usr/bin/env python3
"""Build a compact layout-first Chinese character index for the picker.

Source data: Make Me a Hanzi dictionary.txt (LGPL-3.0-or-later), downloaded
from https://github.com/skishore/makemeahanzi.  Keep COPYING/attribution when
distributing the generated data.  The priority list is the project's local
HSK 3.0 word list; remaining slots are filled from Make Me a Hanzi.
"""
import json
import re
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
URL = "https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt"
TARGET_SIZE = 5000
IDC = set("⿰⿱⿲⿳⿴⿵⿶⿷⿸⿹⿺⿻")
BINARY = set("⿰⿱⿴⿵⿶⿷⿸⿹⿺⿻")
TERNARY = set("⿲⿳")
LAYOUTS = {
    "⿰": "leftRight", "⿱": "topBottom", "⿲": "threePart", "⿳": "threePart",
    "⿴": "surround", "⿵": "surround", "⿶": "surround", "⿷": "surround",
    "⿸": "surround", "⿹": "surround", "⿺": "surround", "⿻": "overlay",
}


def hsk_characters():
    result = []
    for line in (ROOT / "resources/hsk3words.txt").read_text(encoding="utf-8").splitlines():
        # Only numbered entries, not title/header lines.
        if not re.match(r"^\d+\s+", line):
            continue
        for char in line:
            if "\u4e00" <= char <= "\u9fff" and char not in result:
                result.append(char)
    return result


def parse_ids(value, index=0):
    """Return (tree, next index), retaining only real visible components."""
    if index >= len(value):
        return None, index
    char = value[index]
    if char not in IDC:
        return char, index + 1
    count = 3 if char in TERNARY else 2
    children, position = [], index + 1
    for _ in range(count):
        child, position = parse_ids(value, position)
        if child is None:
            return None, position
        children.append(child)
    return (char, children), position


def visible_part(node):
    """Use the immediate visible component; nested IDS becomes its first leaf."""
    if isinstance(node, str):
        return node
    return visible_part(node[1][0])


def root_parts(ids):
    if not ids or ids[0] not in IDC or "？" in ids:
        return None
    tree, end = parse_ids(ids)
    if end != len(ids) or not isinstance(tree, tuple):
        return None
    operator, children = tree
    parts = [visible_part(child) for child in children]
    if any(part in IDC or part == "？" for part in parts):
        return None
    return LAYOUTS[operator], parts


def main():
    cache = ROOT / "resources/makemeahanzi-dictionary.txt"
    if not cache.exists():
        print("Downloading Make Me a Hanzi dictionary data…")
        urllib.request.urlretrieve(URL, cache)
    entries = {}
    component_strokes = {}
    order = []
    for line in cache.read_text(encoding="utf-8").splitlines():
        entry = json.loads(line)
        char = entry.get("character", "")
        if char and entry.get("matches"):
            component_strokes[char] = len(entry["matches"])
        parsed = root_parts(entry.get("decomposition", ""))
        if len(char) != 1 or not ("\u4e00" <= char <= "\u9fff") or not parsed:
            continue
        layout, parts = parsed
        entries[char] = {
            "hanzi": char,
            "pinyin": ", ".join(entry.get("pinyin") or []),
            "gloss": entry.get("definition") or "",
            "layout": layout,
            "parts": parts,
        }
        order.append(char)

    chosen = []
    for char in hsk_characters() + order:
        if char in entries and char not in chosen:
            chosen.append(char)
        if len(chosen) >= TARGET_SIZE:
            break
    if len(chosen) < TARGET_SIZE:
        raise RuntimeError(f"Only found {len(chosen)} usable characters")

    records = [entries[char] for char in chosen]
    frequencies = defaultdict(Counter)
    for record in records:
        frequencies[record["layout"]].update(record["parts"])
    # A small, high-value component palette keeps selection usable.  Any
    # selected component is still supported if later added to the UI.
    components = {
        layout: [part for part, _ in counts.most_common(72)]
        for layout, counts in frequencies.items()
    }
    output = {
        "source": "Make Me a Hanzi dictionary.txt (LGPL-3.0-or-later); filtered locally",
        "count": len(records),
        "characters": records,
        "components": components,
        "componentStrokes": component_strokes,
    }
    target = ROOT / "static/character-index.json"
    target.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {len(records)} characters to {target} ({target.stat().st_size // 1024} KiB)")

if __name__ == "__main__":
    main()
