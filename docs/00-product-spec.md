# Grid & Glory — Product Specification

**Working title:** Grid & Glory: 1v1 Football Trivia Battle
**Arabic title:** التحدي الكروي — Grid & Glory
**Doc owner:** Product + Game Design
**Status:** v1.0 — approved for MVP build
**Last updated:** 2026-11-10

---

## 1. Vision

A 90-second, one-thumb, head-to-head football quiz duel that feels like a **counter-attack**, not a test.
You are not "scoring points". You are **winning the ball, driving up the pitch, and shooting**.

The fantasy is compressed into one sentence:

> *"Answer faster than a stranger in another language and you both watch the same ball go in."*

### Design pillars

| # | Pillar | What it forbids |
|---|--------|-----------------|
| P1 | **Speed is the skill** | Long reading, multi-tap answers, menus during play |
| P2 | **The pitch tells the story** | Abstract score counters as the primary feedback |
| P3 | **Language is invisible** | Any mechanical asymmetry between the English and Arabic player |
| P4 | **One thumb, 60 fps** | Controls outside the bottom-third reach arc; jank on mid-tier Android |
| P5 | **Losable in 90s, learnable in 9** | Tutorials longer than one match |

### Audience

- **Primary (MENA):** 16–34, Arabic-first, watches Saudi Pro League / CAF / UEFA, plays on mid-tier Android (4–6 GB RAM, 60 Hz).
- **Primary (Global):** 18–40, Premier League / UCL viewers, plays in 3–6 minute sessions (commute, queue, halftime).
- **Both:** already play trivia/quiz apps; churn trigger is *waiting*, not losing.

### Session shape

```
Open app → tap PLAY (1 tap) → matchmaking (2–9 s) → 90 s match → result → rematch (1 tap)
Target median session: 2.4 matches (~4 min 20 s)
```

---

## 2. The Match

### 2.1 Clock model

The match clock is **wall-clock during play** and runs through the intro, the question
window and the reveal. It is **frozen** during a Shooting Chance and at half-time
("stoppage time") — so earning a shot never costs you normal-play time, which would
punish the player who just did something good.

| Constant | Value | Notes |
|---|---|---|
| `HALF_MS` | 45 000 | Two halves |
| `ROUND_INTRO_MS` | 1 000 | "Get ready", question preload |
| `ANSWER_WINDOW_MS` | 9 000 | Normal question |
| `REVEAL_MS` | 1 400 | Answer reveal + pitch animation |
| `MIN_ROUND_CLOCK_MS` | 3 500 | **Clock floor per round** (see below) |
| `SHOOT_WINDOW_MS` | 5 000 | Shooting Chance, clock frozen |
| `SHOOT_REVEAL_MS` | 2 200 | Goal / save celebration, clock frozen |
| `HALF_TIME_MS` | 6 000 | Stats card, clock frozen |
| `LAST_ROUND_FLOOR_MS` | 2 500 | Shortest legal final round |

**Per-round charge.** When a round resolves, the clock is charged
`max(time actually taken, 3 500 ms)` — on top of the fixed 1 000 ms intro and 1 400 ms reveal.

That floor is a deliberate anti-exploit measure. Without it a round costs only 2.4 s when
answered instantly, and a scripted client could fit ~19 questions into a half instead of ~6.
More questions means more chances to score, so speed would become unbounded leverage.
With the floor a round costs 5.9–13.4 s and a half holds **6–8 rounds** for everyone:

```
fast player  1.0 + 3.5 + 1.4 = 5.9 s/round  →  7–8 rounds per half
typical      1.0 + 5.0 + 1.4 = 7.4 s/round  →  6 rounds per half
slow         1.0 + 9.0 + 1.4 = 11.4 s/round →  3–4 rounds per half
```

**Half termination.** The half ends at the first round boundary where the clock is
exhausted. If fewer than `ANSWER_WINDOW_MS + intro` remain, the final round's window is
shortened, never below `LAST_ROUND_FLOOR_MS`. A half may overdraw by the tail of its last
round; a half is therefore 45–51 s of regulation.

**Expected volume:** 12–16 normal rounds per match, 0–5 Shooting Chances, wall-clock
2–2.5 minutes per match including reveals and stoppage.

### 2.2 The pitch — 6 zones

The pitch is a **vertical** 2D field in the top 40% of the screen. Your goal is at the bottom,
the opponent's goal at the top. Six horizontal zones, numbered from **your** perspective:

```
        ┌──────────────────────────┐
 ZONE 5 │   ▓▓  GOAL MOUTH  ▓▓    │  ← Shooting Chance zone
        ├──────────────────────────┤
 ZONE 4 │                          │
        ├──────────────────────────┤
 ZONE 3 │                          │
        ├──────────────────────────┤
 ZONE 2 │                          │  ← kickoff after a goal
        ├──────────────────────────┤
 ZONE 1 │                          │
        ├──────────────────────────┤
 ZONE 0 │   ▓▓  YOUR GOAL   ▓▓    │  ← kickoff at match start
        └──────────────────────────┘
```

Both players occupy the same pitch in **two lanes** (you on the reading-start side: left in LTR,
right in RTL). Zones are indexed **per player**, so "zone 5" means "five zones up *my* pitch".

> **Non-negotiable UI decision:** the pitch never flips vertically and attack direction is
> **always upward for the local player**. Only lane assignment mirrors. A vertical, upward-attacking
> pitch is universally readable; mirroring it would make Arabic players attack downward and
> invert every animation, costing readability for zero semantic gain. See `docs/04-ui-ux-spec.md §5`.

### 2.3 Movement rules

Every normal round produces exactly one **delta per player**. There is no partial credit.

| Outcome of the round | Delta | Ball / possession |
|---|---|---|
| Both correct — **earlier** answer | **+2** | Retained |
| Both correct — **later** answer | **+1** | Lost to opponent |
| Correct, and the opponent answered **wrong** | **+2** | Retained |
| Correct, and the opponent **timed out** | **+2** | Retained |
| **Wrong** answer | **−1** | **Turnover** → opponent |
| **No answer** (timeout) | **−1** | **Turnover** → opponent |

`zone = clamp(zone + delta, 0, 5)`

**Jitter grace:** if both players are correct and `|tA − tB| < 120 ms`, both are treated as
**fastest (+2)**. Rationale: at 120 ms we cannot distinguish skill from network asymmetry, and
punishing a coin-flip is the single fastest way to make a fair game feel rigged.

**Late answers:** an answer received after `windowEndsAt` but within `+150 ms` is **accepted for
correctness** but is **ineligible for the +2**. It is recorded with `flaggedLate = true`.
Beyond +150 ms it is `NO_ANSWER`.

### 2.4 Shooting Chance

Reaching **zone 5** immediately suspends normal play and opens a Shooting Chance.

```
zone hits 5
  → SHOOTING_CHANCE state (5 000 ms, difficulty 4–5, match clock frozen)
  → correct  : GOAL. score +1. zone := 2. possession := opponent.
  → wrong    : SAVE.  zone := 3. possession := opponent.
  → timeout  : SAVE.  zone := 3. possession := opponent.
  → cooldown : 8 000 ms before another Shooting Chance can trigger
```

- A Shooting Chance is an **interrupt**, not a round: it does not consume normal-question clock.
- At most **one per player per round**. If both players hit zone 5 in the same round, the earlier
  correct answerer shoots first; the second shot is queued and resolves immediately after.
- If the cooldown is still active when a player hits 5, the shot is **deferred**, not cancelled:
  zone stays at 5 and the shot fires at the first round boundary after cooldown.
- **Goals are the score.** Nothing else is.

### 2.5 Scoring, result, tiebreak

Ranked lexicographically:

1. **Goals** (higher)
2. **Zone reached** (higher)
3. **Correct answers** (higher)
4. **Total correct-answer time** (lower wins — the "clinical" tiebreak)
5. **Draw** (MVP) → replaced by Sudden Death in v1.1

Sudden Death (v1.1, reuses Shooting Chance machinery): alternating 6 s questions, max 3 pairs;
both correct → faster wins; both wrong → repeat; after 3 pairs → draw.

### 2.6 Half-time

A 6 s interstitial at the 45 s mark showing: score, zones, accuracy %, fastest answer.
The clock is frozen. Positions are **retained** across halves; kickoff possession swaps.

---

## 3. Questions

### 3.1 The five formats

| Format | Key | Mechanic | Why it exists | Share |
|---|---|---|---|---|
| **Multiple Choice** | `mc` | 4 text options | The workhorse; fastest to author | 40% |
| **Career Path** | `career_path` | Club sequence → name the player | Recognises *journeyman* knowledge, not just headline stats; strong cross-league appeal | 15% |
| **Emoji Storyline** | `emoji_story` | Emoji sequence → identify player / club / event | Language-free, instant, highly shareable; **the fairest possible cross-language format** | 15% |
| **Blur & Reveal** | `blur_reveal` | Progressive unblur → answer as early as you dare | Pure speed tension; the only format where waiting is a strategy | 15% |
| **Stat High/Low** | `stat_highlow` | Two entities, pick the higher | MENA-legible (titles, caps, goals); cheap to author at scale | 15% |

### 3.2 Difficulty curve

`difficulty ∈ 1..5`. Per match, the server pre-draws a 16-question pool following:

| Round # | Target difficulty |
|---|---|
| 1–2 | 2 |
| 3–5 | 2–3 |
| 6–9 | 3 |
| 10+ | 3–4 |
| Shooting Chance | 4–5 |

A question may be served at most **once per player per 30 days** (`question_seen` table), and never
twice in one match. Both players always receive the **same question ID** — only the rendering locale differs.

### 3.3 Regional balance

The bank must satisfy, per 100 published questions:

- **≥ 35** MENA / African (CAF, Saudi Pro League, AFCON, Arab legends, Egyptian/Saudi clubs)
- **≥ 35** Global (UEFA, FIFA World Cup, major leagues)
- **≥ 20** either, but explicitly tagged `REGIONAL_BRIDGE` (a global player who played in MENA, or vice versa — e.g. Ronaldo→Al Nassr, Mané→Al Nassr, Mahrez→Al Ahli)

Regional balance is a **build-time assertion** in the bank validator, not a guideline.

### 3.4 Cross-language fairness rules

These are hard requirements, enforced by `db/validate.mjs`:

1. **Locale-neutral answer keys.** The correct answer is `answerOptionId`, never an index.
   Option order is shuffled independently per player, per round.
2. **Character-count parity.** `arChars / enChars ∈ [0.55, 1.85]` (warn outside `[0.70, 1.50]`).
   Protects reading speed from becoming a language tax.
3. **No images containing text.** Blur & Reveal assets must be text-free; otherwise one locale gets
   a free hint. Enforced by an asset-review checklist flag.
4. **Emoji sequences are bidi-isolated** with U+2066 (LRI) … U+2069 (PDI) so an Arabic UI does not
   render the sequence right-to-left.
5. **No locale-specific wordplay, puns, or abbreviations** that do not survive translation
   (e.g. "the Red Devils" as a clue).
6. **Same difficulty, one record.** A question is one DB row with both locales. There is no
   "Arabic version of question 42" — divergence is structurally impossible.
7. **Linguist sign-off** for `ar` is a required field (`localization.verifiedBy`), not optional metadata.

### 3.5 Authoring & ops

- Draft → `in_review` → `published`, with `reviewedBy` and `arReviewedBy` both required to publish.
- `stats.dataAsOf` required on any question containing a countable fact (Stat High/Low), so a
  pending transfer or a new title does not silently make the bank wrong.
- Every publish bumps `version`; matches store the `questionVersion` they served, so a disputed
  match can be replayed against the exact text the players saw.
- **Retirement:** a question with `globalCorrectRate > 0.95` (too easy) or `< 0.15` (broken) is
  auto-flagged after 200 serves.

---

## 4. Progression (MVP scope)

**In:** Elo-style rating (Glicko-2 fields reserved), 3 placements, ranked ladder reset per season,
one "Daily Duel" (best-of-5 vs the same ghost question set, no opponent needed — retention hook).

**Out of MVP (deliberately):** friends list, chat, tournaments, cosmetics shop, battle pass,
clubs/guilds, spectator mode, voice, ads.

> **Monetization stance:** none in MVP. Trivia fairness is the product; anything sold must be
> cosmetic-only and must never touch question access, timers, or matchmaking. This is written down
> because it is the most likely thing a growth team will try to break later.

---

## 5. Success metrics

| Metric | Target (day 30) | Kill threshold |
|---|---|---|
| Match completion rate | ≥ 92% | < 80% |
| Median matchmaking wait | ≤ 6 s | > 12 s |
| D1 / D7 retention | 32% / 12% | 20% / 6% |
| Rematch rate (same session) | ≥ 45% | < 25% |
| Answer accuracy | 55–70% | outside 45–78% |
| **Locale win-rate delta (EN vs AR)** | **±3 pts** | **±8 pts** |
| p95 answer→ack latency | ≤ 180 ms | > 350 ms |
| Crash-free sessions | ≥ 99.5% | < 98.5% |

The locale win-rate delta is the canary metric for the entire product thesis. It is instrumented
from day one and reviewed weekly.

---

## 6. Explicit non-goals

- Not a football simulator; no match engine, no live data dependency at play time.
- Not a chat app; emote pings only (4 canned reactions) because moderation of cross-language
  text chat in a 90-second game is a cost centre, not a feature.
- Not portrait-web; mobile only.
- No offline matches in MVP (the game *is* the opponent).

---

**Related docs:** `01-technical-architecture.md` · `02-database-schema.md` · `03-realtime-matchmaking.md` · `04-ui-ux-spec.md` · `05-frontend-components.md` · `06-mvp-roadmap.md`
