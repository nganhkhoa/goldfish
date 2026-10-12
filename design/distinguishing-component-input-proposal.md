# Proposal: Distinguishing-Component-First Character Input

## Status

**Proposal for a later iteration.** The current layout/family picker remains in place. This document describes a replacement or complementary query path designed for learners who can recognize a character’s overall shape but do not know radical terminology.

## Problem

The current left–right flow begins with the component in the first IDS position. That is often a small, high-frequency semantic radical:

```text
僚 = 亻 + 尞
```

Selecting `人 · 亻` creates a very large candidate set. The user is then asked to visually inspect hundreds of characters that begin with the same small radical. This defeats the purpose of the picker.

The same problem occurs with many frequent left-side or top-side components:

- `亻` person
- `氵` water
- `扌` hand
- `忄` heart
- `讠` speech
- `纟` thread
- `钅` metal
- `月 / ⺼` flesh

These often communicate category, but not enough identity to find an unfamiliar character efficiently.

## Product Principle

**Let the learner search by the most visually distinctive, information-rich part of the character first.**

The input should treat a small/common radical as optional context, not the primary key. The learner should be able to say: “I know the large right-hand shape,” even if they cannot name or distinguish the small left radical.

This is not a radical dictionary. It is a visual narrowing tool.

## Proposed Interaction

### Step 1 — Choose the general form

Keep the existing structural choice:

- left + right
- top + bottom
- enclosure
- three parts
- overlay / other

### Step 2 — Choose the part that stands out

Instead of immediately asking for *left* or *top*, ask:

> Which part is easier to recognize?

For two-part layouts, offer two large positional choices:

| Layout | Choices |
|---|---|
| Left + right | **small left part** / **large right part** |
| Top + bottom | **small top part** / **large bottom part** |
| Enclosure | **outer frame** / **inside shape** |
| Three parts | **left**, **middle**, **right**, plus **the largest-looking part** |
| Overlay | **base shape** / **added mark or shape** |

The UI should recommend the likely distinctive position. For left–right characters, this is commonly the right component; for top–bottom characters, it is commonly the bottom component.

### Step 3 — Browse a compact family for that position

Show visual families appropriate to the selected position. These are not numbered catch-all buckets. Each family must have a human-readable visual label and a visible sample.

Examples for **large right part**:

- **People and actions** — 尔, 也, 可, 古, 艮
- **Clothes, food, home** — 衣, 良, 食, 容, 家
- **Nature and material** — 青, 木, 火, 石, 票
- **Shapes and tools** — 交, 兑, 旁, 包, 工
- **Complex familiar shapes** — 尞, 兼, 鬼, 畐, 复

The exact family taxonomy should be created from usability testing, not automatically generated from Unicode decomposition order.

### Step 4 — Show candidates immediately

Selecting one distinctive component should show candidates immediately, in a scrollable, frequency-ranked list. The small/common radical becomes an optional second filter:

```text
Left + right
→ large right part
→ Complex familiar shapes
→ 尞
→ 僚, 潦, 燎, 瞭, …
→ optional: add left radical 人 · 亻
→ 僚
```

The first result list must be bounded visually (for example, 3–5 rows with scrolling) rather than truncated. A user can still find a less frequent character without being forced through another family selection.

## Example: 僚

Current problematic route:

```text
Left + right → People & body → 人 · 亻 → hundreds of results
```

Proposed route:

```text
Left + right
→ large right part
→ Complex familiar shapes
→ 尞
→ candidates: 僚, 潦, 燎, 瞭, …
→ optional refinement: left is 人 · 亻
→ 僚
```

The proposed route asks the learner to recognize the feature that separates `僚` from most other person-radical characters.

## Component Model

### Store both structural positions and visual importance

The current generated index stores only the root IDS layout and immediate component list:

```json
{
  "hanzi": "僚",
  "layout": "leftRight",
  "parts": ["亻", "尞"]
}
```

Extend each record with position-aware and learner-facing metadata:

```json
{
  "hanzi": "僚",
  "layout": "leftRight",
  "parts": ["亻", "尞"],
  "positions": {
    "left": "亻",
    "right": "尞"
  },
  "primarySearchParts": ["尞", "亻"],
  "partGroups": {
    "亻": "人",
    "尞": "尞"
  }
}
```

`primarySearchParts` is an ordered list, not an assertion about etymology. It exists solely for interaction ranking.

### Heuristics for initial ranking

Use simple, reviewable rules at first:

1. Normalize component variants into existing learner groups (`亻 → 人`, `氵 → 水`, etc.).
2. Mark common short radicals as low-information components.
3. For binary left–right and top–bottom structures, prefer the non-low-information sibling.
4. Prefer a component whose subtree has more visible strokes or nested parts, when data is available.
5. Allow a small manual override table for common/ambiguous characters.

The system must never hide the other component; it should merely lead with the more useful one.

## Ranking and Results

### Candidate order

Candidate results should be ranked by:

1. exact distinctive-component match;
2. match to an optional second component/group;
3. character frequency / HSK priority;
4. availability in the application dictionary;
5. stable Unicode/codepoint fallback.

### Result presentation

Each result tile should show only:

- character;
- optional pronunciation;
- optionally a compact decomposition hint on hover/tap.

The tile should append the character to the active dictionary search input, not replace existing query text.

### Avoid artificial limits

Do not use `List.take` to silently make candidates unreachable. Use a fixed-height, scrollable candidate panel instead.

## Data and Index Changes

1. Update `scripts/build_character_index.py` to preserve the parsed IDS tree, not only its root children.
2. Generate positional labels by layout (`left/right`, `top/bottom`, `outer/inner`, etc.).
3. Generate a `primarySearchParts` ordering using the initial heuristics.
4. Add a curated `component-family` source file. It should group recognizable shapes, including complex components, and must not use names such as `More shapes 1`.
5. Generate the Elm/JSON family lookup from that curated source.
6. Retain and run an audit script that verifies every shipped indexed character is reachable from at least one position and family.
7. Extend the audit to report:
   - whether a character has a distinctive-first route;
   - candidate-set size after its first recommended choice;
   - characters whose recommended first choice exceeds a threshold, e.g. 40 candidates.

## Accessibility and Learner Guidance

- Use visual samples in families, not radical-only terminology.
- Present variant groups visibly: `人 · 亻`, `水 · 氵`, `月 · ⺼`.
- Describe choices by position and visual role: “large right part,” not “phonetic component.”
- Preserve a route for users who recognize only the small radical.
- Keep handwriting/OCR as a future fallback for characters whose distinctive part is still too complex to identify.

## Open Questions

1. What frequency source should order candidate characters?
2. What candidate count feels usable before the UI should suggest a second filter?
3. Should component families be shared across Chinese and Japanese kanji, or have language-specific curation?
4. How should simplified/traditional component variants be grouped?
5. Can IDS subtree complexity be used reliably as a proxy for what users perceive as the “big” part?
6. How should single-component characters and non-standard decompositions enter the flow?

## Phased Implementation

### Phase 1 — Data and audit

- Add positional component metadata and `primarySearchParts`.
- Create a curated family source file.
- Add the recommended-route/candidate-count audit.
- Do not change the current production UI yet.

### Phase 2 — Prototype in the inline picker

- Add “which part stands out?” after layout selection.
- For left–right and top–bottom only, default to the high-information position.
- Display scrollable candidates immediately after one component selection.
- Make the low-information radical an optional refinement.

### Phase 3 — Test and curate

- Test a representative set of beginner/intermediate characters, including 僚, 税, 退, 凳, 依, and 脖.
- Track first-choice candidate counts and completion rate.
- Expand/adjust visual families based on failures.

### Phase 4 — Fallback input

- Add handwriting or camera/OCR input for cases that remain difficult after structural search.

## Acceptance Criteria

- A user can find `僚` by selecting its layout and the right-side `尞`, without first selecting `亻`.
- A common small radical never forces a candidate list of hundreds before the user can choose the more distinctive sibling.
- Every character in the shipped index has at least one reachable family path, verified in CI or a reproducible local script.
- No user-facing family is a numbered arbitrary bucket such as “More shapes 12.”
- Candidate panels are scrollable rather than silently truncated.
- Choosing a character appends it to the active dictionary search field.
