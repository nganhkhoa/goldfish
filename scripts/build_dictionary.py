#!/usr/bin/env python3
"""Build browser-ready compressed dictionary stores from resources/."""
import csv, gzip, hashlib, json, re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "resources"
OUT = ROOT / "goldfish"


def stable_id(lang, *parts):
    value = "|".join((str(x or "").strip() for x in parts))
    return hashlib.sha1(f"{lang}|{value}".encode("utf-8")).hexdigest()[:16]


def load_levels(path, word_col, level_col):
    result = {}
    with path.open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            word = (row.get(word_col) or "").strip()
            level = (row.get(level_col) or "").strip()
            if word and level:
                result[word] = level
    return result


def chinese():
    # CEDICT lines: traditional simplified [pinyin] /definition/
    records = []
    for line in (RES / "cedict_1_0_ts_utf-8_mdbg.txt").read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^(\S+) (\S+) \[(.*?)\] /(.*)/$", line)
        if not m:
            continue
        traditional, simplified, pinyin, meaning = m.groups()
        records.append({"id": simplified,
                        "simplified": simplified, "traditional": traditional,
                        "pinyin": pinyin, "zhuyin": None, "meaning": meaning,
                        "hsk": 0})
    levels = {}
    current_level = 0
    for line in (RES / "hsk3words.txt").read_text(encoding="utf-8").splitlines():
        header = re.match(r"^([一二三四五六七八九十]+)级词汇表$", line.strip())
        if header:
            chinese_levels = {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6}
            current_level = chinese_levels.get(header.group(1), 7)
            continue
        m = re.match(r"^\d+\s+(.+)$", line.strip())
        if m and current_level:
            for word in m.group(1).split("｜"):
                levels[word.split("（")[0].strip()] = current_level
    for r in records:
        r["hsk"] = levels.get(r["simplified"], levels.get(r["traditional"], 0))
    return records


def japanese():
    # JLPT classification is retained from the project's curated CSV.
    levels = {}
    with (RES / "jlpt.csv").open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            if row.get("expression"):
                tags = row.get("tags", "")
                # The source uses both JLPT_1..JLPT_5 and JLPT_N1..JLPT_N5.
                m = re.search(r"JLPT_(?:N)?([1-5])", tags)
                if m: levels[row["expression"]] = int(m.group(1))
    records = []
    for event, entry in ET.iterparse(RES / "JMdict", events=("end",)):
        if entry.tag != "entry": continue
        seq = entry.findtext("ent_seq", "")
        words = [x.text for x in entry.findall("./k_ele/keb") if x.text]
        readings = [x.text for x in entry.findall("./r_ele/reb") if x.text]
        word = words[0] if words else (readings[0] if readings else "")
        if not word: entry.clear(); continue
        # JMdict stores localized glosses with the XML namespace key
        # ``{http://www.w3.org/XML/1998/namespace}lang``. Keep only the
        # English glosses; the previous check missed the namespace and let
        # Dutch, German, French, etc. leak into the Japanese database.
        english_glosses = []
        for gloss in entry.findall("./sense/gloss"):
            language = gloss.attrib.get("{http://www.w3.org/XML/1998/namespace}lang")
            if gloss.text and (language is None or language == "eng"):
                english_glosses.append(gloss.text.strip())
        meaning = "; ".join(english_glosses)
        records.append({"id": word, "word": word,
                        "furigana": readings[0] if readings else "",
                        "alternatives": words[1:] + readings[1:], "meaning": meaning,
                        "jlpt": levels.get(word, 0)})
        entry.clear()
    return records


def korean():
    # Kengdic is the Korean-English source. The XML resources/ files are the
    # Korean-Korean Basic Dictionary and must not be used for the app cards.
    levels = {}
    with (RES / "topik.tsv").open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            word = re.sub(r"\d+$", "", (row.get("word") or "").strip())
            level = (row.get("topik_level") or "").strip()
            if word and level in ("A", "B"):
                levels[word] = 1 if level == "A" else 2

    records = []
    with (RES / "kengdic.tsv").open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            word = (row.get("surface") or "").strip()
            meaning = (row.get("gloss") or "").strip()
            if not word or not meaning:
                continue
            records.append({
                "id": str(row.get("id") or stable_id("ko", word, meaning)),
                "word": word,
                "hanja": (row.get("hanja") or "").strip() or None,
                "meaning": meaning,
                "topik": levels.get(re.sub(r"\d+$", "", word), 0)
            })
    return records


def write(lang, records):
    target = OUT / f"{lang}.json.gz"
    with gzip.open(target, "wt", encoding="utf-8", compresslevel=9) as f:
        json.dump(records, f, ensure_ascii=False, separators=(",", ":"))
    print(lang, len(records), target, target.stat().st_size // 1024, "KiB")

if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    write("cn", chinese())
    write("jp", japanese())
    write("ko", korean())
