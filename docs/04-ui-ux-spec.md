# UI / UX Specification

**Platform:** mobile portrait only · **Base device:** 390 × 844 dp (iPhone 14 / Pixel 7 class)
> **See it rendered:** [`design/match-screen.html`](../design/match-screen.html) — four frames
> (EN playing, AR playing, EN reveal, AR Shooting Chance) built from this document's own numbers.
> Open it in a browser; no build step, no external assets.

**Component breakdown:** [`docs/05-frontend-components.md`](05-frontend-components.md)

---

## 1. Non-negotiables

| # | Rule | Consequence if broken |
|---|---|---|
| 1 | Everything playable sits in the **bottom 60%** | Thumb cannot reach; the game is unplayable one-handed |
| 2 | The pitch is **never interactive** | Dead-zone taps steal answers |
| 3 | Attack direction is **always upward for the local player** | Arabic players would attack downward and every animation inverts |
| 4 | **Timers and numerals never mirror** | "2 – 1" becoming "1 – 2" is a wrong scoreline |
| 5 | Answer targets are **≥ 56 dp tall, ≥ 8 dp apart** | Mis-taps inside a 9 s window are indistinguishable from not knowing |
| 6 | Text must survive **200% accessibility scale** | Android users who need it most get a broken layout |
| 7 | Colour is **never the only signal** | ~8% of male players are colour-blind |

## 2. Screen inventory

| Screen | Purpose | Primary action |
|---|---|---|
| Home | Language toggle, one PLAY button | Tap PLAY |
| Matchmaking | Waiting, opponent-found reveal | Cancel |
| **Match** | The game | Answer / do nothing |
| Result | Score, rating change, rematch | Rematch |
| Daily Duel | Best-of-5 without an opponent | Play |
| Settings | Locale, numerals, haptics, motion, account | — |

## 3. Home — the language toggle

```
┌──────────────────────────────────┐
│  ⌂                        ⚙      │
│                                  │
│         GRID & GLORY             │
│      التحدي الكروي               │   ← both titles always shown, no tab switch
│                                  │
│   ┌──────────────┬─────────────┐ │
│   │  English  ▍  │      ع      │ │   ← segmented control, 44 dp tall
│   └──────────────┴─────────────┘ │
│                                  │
│   ╔════════════════════════════╗ │
│   ║         ▶  PLAY            ║ │   ← 64 dp, full width, bottom 40%
│   ╚════════════════════════════╝ │
│   ┌────────────────────────────┐ │
│   │  Daily Duel      🔥 3      │ │
│   └────────────────────────────┘ │
│   Rating 1 240        ⓘ EN · EU  │
└──────────────────────────────────┘
```

- Tapping a segment swaps **locale, text direction, and every string in place**, with no reload,
  no flash of the old layout. The `Directionality` ancestor is rebuilt; the pitch is not on screen.
- Default on first launch: the device locale if it is `ar`, else `en`.
- Persisted locally *and* pushed to `player_settings`, so a reinstall does not reset it.
- The toggle stays visible in the top-right (top-left in RTL) of Home only — it is a deliberate,
  discoverable choice, never a modal buried in settings.

## 4. Match screen — the 40 / 60 split

```
┌──────────────────────────────────────────┐
│ ░░░ safe area 47 dp ░░░                  │
├──────────────────────────────────────────┤
│  YOU 2           45:00 ▾            1  OPP│  44 dp  ← HUD overlays the pitch
│  ┌────────────────────────────────────┐  │
│  │ Z5  ══════════ GOAL ══════════════ │  │
│  │ Z4                                 │  │
│  │ Z3        ▲you            ▲opp     │  │  PITCH
│  │ Z2                                 │  │  = 40% of
│  │ Z1                                 │  │  available
│  │ Z0  ══════════ GOAL ══════════════ │  │  height
│  └────────────────────────────────────┘  │
├──────────────────────────────────────────┤
│  ROUND 4 · 2/2                        ⏱ │  40 dp
│  ┌────────────────────────────────────┐  │
│  │  Which club has won the most       │  │
│  │  UEFA Champions League titles?     │  │  QUESTION
│  │                                    │  │  min 96 dp
│  └────────────────────────────────────┘  │
│  ┌────────────────────────────────────┐  │
│  │  Real Madrid                    ●  │  │
│  ├────────────────────────────────────┤  │  4 × 56 dp
│  │  AC Milan                          │  │  gap 8 dp
│  ├────────────────────────────────────┤  │
│  │  Bayern Munich                     │  │
│  ├────────────────────────────────────┤  │
│  │  Liverpool                         │  │
│  └────────────────────────────────────┘  │
│ ░░░ safe area 34 dp ░░░                  │
└──────────────────────────────────────────┘
```

### 4.1 Vertical budget (390 × 844)

| Region | Height | Notes |
|---|---|---|
| Safe areas | 47 + 34 | `MediaQuery.padding` |
| Available | **763** | |
| Pitch | **305** (40%) | HUD overlays the top 44 dp of it |
| Quiz panel | **458** (60%) | |
| ├ round label row | 44 | round number, "2/2" legs, timer chip |
| ├ question card | 120 flex (min 96) | shrinks first under text pressure |
| ├ answers | 240 | 4 × 54 + 3 × 8 |
| └ padding | 54 | 16 top/bottom + 11 breathing |

**Overflow ladder** (in order, applied when content does not fit):

1. Question card shrinks to 96 dp.
2. Question card scrolls internally (last resort, and only for `career_path` club lists).
3. Answer button height reduces to 52 dp (never below 48).
4. Answer text clamps to 2 lines with ellipsis — **only** for option text, never for the prompt.

Arabic strings run, on average, 0.88× the English character count (measured across the seed bank:
mean parity 0.88), but Arabic renders **taller** — line height 1.7 vs 1.4. The button height math
above uses the taller Arabic metrics as the constraint, not English.

### 4.2 HUD

- Left: your score (goals) in 28 sp, tabular figures.
- Centre: match clock `MM:SS`, 16 sp, tabular; turns amber under 15 s.
- Right: opponent score.
- A possession dot (6 dp) sits next to whoever holds the ball.
- HUD is an **overlay** on the pitch, not a row above it — this keeps the pitch a true 40% rather
  than 40% minus chrome.

### 4.3 The pitch

Six zones, bottom to top for the local player. Two lanes: you on the reading-start side
(left in LTR, **right** in RTL), opponent opposite.

- Zone bands: alternating grass stripes, 8% luminance shift, no hard borders.
- Zone numbers are **not** drawn during play (they are noise); they appear only in the first
  tutorial match and in the result card.
- Avatars: 44 dp circular tokens with a 2 dp ring in the player's lane colour
  (you `#38BDF8`, opponent `#F472B6` — a deuteranopia-safe pair, not red/green).
- The ball is a 10 dp dot that travels between the two avatars on possession change.
- Goal mouth: a lighter band with a subtle net pattern at zones 0 and 5.

### 4.4 Quiz panel states

| State | Visual |
|---|---|
| `round_intro` | Question card shows a shimmer skeleton; answers are disabled and 40% opacity |
| `question_open` | Answers enabled; timer ring sweeps from the chip |
| `answered` | The chosen answer locks (checkmark, no colour-only signal), others dim to 45%; the opponent gets "they answered" pulse only |
| `round_reveal` | Correct answer turns green **with a check icon**; the wrong pick turns red **with an ✕**; deltas float up |
| `shooting_chance` | Panel is replaced by a full-width "SHOOTING CHANCE" band + the question; the non-shooter sees a "defending" lock state and a disabled answer list |
| `half_time` | Stats card overlays the pitch; the quiz panel dims |

### 4.5 Answer buttons — the most important control in the game

- Full-width rows, single column. A 2×2 grid halves the width of Arabic text and causes wrapping
  that looks like a different question.
- 56 dp tall, 8 dp gaps, 16 dp horizontal padding, 16 dp radius.
- Pressed: scale 0.98 for 90 ms + light haptic. No colour flash before submission (the server has
  not confirmed yet — optimistic colouring is a lie that costs trust).
- Selected: 2 dp border + check glyph on the trailing edge (mirrored in RTL).
- Disabled during `round_intro`, `round_reveal`, and — for the defender — during a Shooting Chance.

## 5. LTR ↔ RTL: the rule matrix

This is the part that decides whether the Arabic build feels native or like a mirrored English app.

### 5.1 What MUST mirror

| Element | Mechanism |
|---|---|
| All text alignment and reading order | `Directionality` from `Locale` |
| Horizontal padding/margins | `EdgeInsetsDirectional.only(start:, end:)` |
| Row/Column child order | `Row` follows ambient direction automatically |
| Directional icons (back, chevron, send) | `Icon(..., matchTextDirection: true)` — **not** a manual transform |
| Answer button checkmark | Trailing edge via `AlignmentDirectional.centerEnd` |
| Progress / timer fill direction | `FractionallySizedBox` inside a direction-aware stack |
| Lane assignment on the pitch | Your lane = reading-start side |
| Scoreline container | Mirrored so "you" keeps the reading-start side |
| Page transitions | `CupertinoPageRoute` / `PageTransitionsTheme` respect direction |

### 5.2 What MUST NOT mirror

| Element | Why |
|---|---|
| **Pitch vertical axis** | Attack is upward for the local player, in every language. Mirrored, Arabic players run toward their own goal and the goal celebration plays upside-down. |
| **Avatar sprites** | Flip the container, never the artwork. A mirrored face reads as a different person. Use `Transform.scale(scaleX: -1)` on the *frame*, keep the sprite unflipped. |
| **Timer ring sweep** | Clockwise in both. A counter-clockwise clock is a different metaphor, not a translated one. |
| **Numeral sequences** | `2 – 1` must not reorder. Digits are LTR even in Arabic text. |
| **The match clock and scores** | `45:00` is `45:00`. |
| **Emoji sequences** | Already bidi-isolated server-side with U+2066…U+2069. The client must not re-order them. |
| **The pitch zone indices** | Zone 5 is the opponent's goal on both sides. |

### 5.3 Bidi hazards, with fixes

| Hazard | Example | Fix |
|---|---|---|
| Dynamic value inside an Arabic sentence | `"الفائز 2022"` | Wrap in `\u2066 … \u2069` (LRI/PDI) |
| Score ranges | `7–1` can reorder to `1–7` | Isolate, or render as separate `Text` spans |
| Percentages / minutes | `%68` vs `68%` | Isolate the number run |
| Mixed English club names in Arabic UI | "Real Madrid" inside `RTL` text | Isolate as an LTR run; do not let it inherit the paragraph direction |
| Punctuation drift | A trailing period jumps to the wrong side | Let the framework place it; never hard-code `'. '` concatenation |
| **Letter-spacing on Arabic** | Breaks the cursive joins between letters | **`letterSpacing: 0` for `ar`, always.** Never apply a global tracking token to Arabic. |
| Synthetic bold on Arabic | Smears the joins | Use real font weights only |

### 5.4 Numerals

MENA sports UIs use Western digits in scores and clocks almost universally, and mixing systems
inside one match is worse than either choice. So:

- **Default: Western digits (`0-9`) in both locales.**
- Offer `numeral_style: arabic_indic` in Settings for users who want `٠١٢٣`, applied via
  `NumberFormat` with a locale override — but **the match clock and scoreline stay Western**
  even when the setting is on, because two numeral systems on one screen is worse than none.
- Always tabular figures for anything that changes in place (clock, score, deltas), or the layout
  jitters every second.

## 6. Typography

| | English | Arabic |
|---|---|---|
| Family | Inter (or SF Pro / Roboto) | IBM Plex Sans Arabic (fallback Noto Kufi Arabic) |
| Display | 32 / 38 | 30 / 46 |
| Title | 22 / 28 | 22 / 38 |
| Body | 16 / 24 | 17 / 30 |
| Label | 13 / 18 | 14 / 24 |
| Line height | 1.4 | **1.65–1.8** |
| Letter spacing | 0 to +0.2 | **0** (non-negotiable) |
| Weight | 400 / 600 / 800 | 400 / 600 / 700 (no 800 — too heavy for Arabic) |

Arabic needs a larger line box for the same optical size. Reusing the English line height clips
diacritics and descenders, so line height is a **per-locale token**, not a global one.

## 7. Colour

| Token | Value | Use |
|---|---|---|
| `bg/base` | `#0B1220` | App background |
| `bg/raised` | `#131C2E` | Cards |
| `pitch/grass-a` | `#1B7F4B` | Pitch stripe |
| `pitch/grass-b` | `#17703F` | Pitch stripe |
| `accent` | `#FFC24B` | Primary CTA, timer warning |
| `you` | `#38BDF8` | Your lane, your avatar ring |
| `opponent` | `#F472B6` | Opponent lane |
| `correct` | `#2FBF71` | Reveal only — always paired with ✓ |
| `wrong` | `#E5484D` | Reveal only — always paired with ✕ |
| `text/primary` | `#F2F6FF` | 14.8:1 on `bg/base` |
| `text/secondary` | `#9FB0CC` | 6.1:1 on `bg/base` |

Contrast floor 4.5:1 for body text, 3:1 for ≥ 24 sp. Colour is never the sole carrier of meaning:
correct/wrong always carry a glyph and a pitch movement.

## 8. Motion

| Interaction | Duration | Curve |
|---|---|---|
| Answer press | 90 ms | `easeOut` |
| Zone advance | 420 ms | `easeOutCubic`, with a 300 ms arc hop |
| Zone knock-back | 380 ms | `easeInOut`, with a stumble |
| Goal | 900 ms | ball to net, net ripple, confetti burst |
| Save | 700 ms | ball deflects, keeper flash |
| Reveal stamp | 180 ms | scale 1.1 → 1.0 |
| Half-time card | 300 ms in / 200 ms out | fade + lift |

**Reduced motion** (`MediaQuery.disableAnimations` or the app setting): zone changes become instant
position updates with a 120 ms cross-fade, celebrations become a static badge. Never remove the
information — only the movement.

## 9. Accessibility

- Every answer is a semantic button with an explicit label: `"Answer: Real Madrid"`.
- The pitch has a `Semantics` summary that updates on change:
  `"You are on zone 3. Opponent on zone 2. You have the ball."`
- The timer exposes an `Animatable`-free text value and a `Semantics(label: "8 seconds remaining")`
  rather than relying on the ring.
- Focus order follows reading direction.
- 200% text scale is a CI screenshot test for **both** locales (see roadmap, week 3).
- Haptics: light on press, medium on correct, heavy on goal — all gated on the settings toggle.

## 10. Empty, loading and error states

| Situation | Copy (EN / AR) |
|---|---|
| No connection | "You're offline. Check your connection." / "أنت غير متصل. تحقق من اتصالك." |
| Matchmaking > 20 s | "Still looking… widening the search." / "ما زلنا نبحث… نوسّع نطاق البحث." + Cancel |
| Opponent left | "Opponent disconnected — 25 s to return." / "انقطع اتصال الخصم — 25 ثانية للعودة." |
| Match voided | "Match cancelled. No rating change." / "أُلغيت المباراة. لا تغيير في التصنيف." |
| Asset failed | Blur & Reveal falls back to the text-only variant of the question, never an empty card |
