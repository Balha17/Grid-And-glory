# Grid & Glory — التحدي الكروي

**1v1 football trivia battle.** 90 seconds, two halves, one thumb. An English speaker and an
Arabic speaker are matched against each other and asked **the same question at the same instant**,
each in their own language.

This repository is the complete core technical specification plus a working match engine, a
validated bilingual question bank, and the Flutter component layer.

---

## What's in the box

| Deliverable | Where | What it is |
|---|---|---|
| **Product & game design** | [`docs/00-product-spec.md`](docs/00-product-spec.md) | Rules, 6-zone pitch model, clock math, tiebreaks, fairness rules |
| **Technical architecture** | [`docs/01-technical-architecture.md`](docs/01-technical-architecture.md) | Stack, topology, latency budget, anti-cheat, failure modes |
| **Dual-language DB schema** | [`docs/02-database-schema.md`](docs/02-database-schema.md) · [`db/schema/migrations.sql`](db/schema/migrations.sql) | Postgres DDL + the JSONB/column split |
| **Question JSON contract** | [`db/schema/question-bank.schema.json`](db/schema/question-bank.schema.json) | JSON Schema 2020-12, all five formats |
| **Bilingual question bank** | [`db/seed/bank.en-ar.v1.json`](db/seed/bank.en-ar.v1.json) | 54 questions, EN+AR, all five formats, global + MENA/African |
| **Bank validator + pipeline** | [`db/validate.mjs`](db/validate.mjs) · [`db/normalize.mjs`](db/normalize.mjs) · [`db/shuffle-answers.mjs`](db/shuffle-answers.mjs) | CI gate for fairness invariants |
| **WebSocket protocol & state machine** | [`docs/03-realtime-matchmaking.md`](docs/03-realtime-matchmaking.md) | Message catalogue, transitions, pseudocode |
| **Match engine + gateway (TypeScript)** | [`server/src/`](server/src) | Room actor, scoring, token, renderer, WebSocket gateway |
| **Runnable server + smoke client** | [`server/src/server.ts`](server/src/server.ts) · [`server/src/smoke.ts`](server/src/smoke.ts) | `npm run serve` / `npm run smoke` |
| **UI/UX spec** | [`docs/04-ui-ux-spec.md`](docs/04-ui-ux-spec.md) | 40/60 layout, LTR↔RTL rule matrix, tokens, a11y |
| **Layout proof (visual)** | [`design/match-screen.html`](design/match-screen.html) | EN + AR match screen rendered from the spec's own numbers |
| **Flutter app shell** | [`docs/05-frontend-components.md`](docs/05-frontend-components.md) · [`app/`](app) | Locale plumbing, pitch painter, reducer, socket transport, screens |
| **4-week MVP roadmap** | [`docs/06-mvp-roadmap.md`](docs/06-mvp-roadmap.md) | Day-by-day plan + Play Store checklist |
| **Release runbook** | [`RELEASE.md`](RELEASE.md) | Keystore → APK/AAB → Play Console → 14-day test → rollout |

---

## Verify it

Everything here runs. No Docker, no database, no Flutter SDK required for the engine.

```bash
npm install
npm run verify          # typecheck + 57 tests + schema + bank + Flutter structure
npm run demo            # play a full match and print the play-by-play
npm run bench           # measure engine capacity (200 concurrent matches)
npm run serve           # boot the WebSocket gateway on :8080
npm run smoke           # two real clients play a full match over the wire

# APK: see app/README.md — `.github/workflows/android.yml` builds it on CI
```

Expected:

```
> tsc -p tsconfig.json                      (clean)

✓ scoring: 20 passed
✓ matchmaking: 10 passed
✓ match: 13 passed
✓ gateway: 14 passed
✓ schema: 54 questions validate against JSON Schema 2020-12
✓ app: 13 Dart files, balance + imports + l10n parity + RTL rules

✓ PASSED        questions: 54 · published: 54
                regional split: MENA/AFRICA/bridge 24/54 (44%), global 31/54 (57%)
                answer positions: [18, 15, 9, 12]
                parity mean 0.881 (min 0.702, max 1.263)
```

```bash
npm run demo
```

```
   0.0s  🟢 KICKOFF  Alice (EN) vs عمر (AR) — same question, two languages
   1.0s  R 1 [emoji_story/2] Which tournament do these symbols describe?

  ── one question, two locales (id q_emoji_wc2022) ──
   EN [ltr] Which tournament do these symbols describe?
   AR [rtl] أي بطولة تصفها هذه الرموز؟
   EN options: 2022 World Cup · Euro 2020 · 2018 World Cup · AFCON 2019
   AR options: كأس العالم 2022 · كأس أمم أفريقيا 2019 · كأس العالم 2018 · يورو 2020

   1.0s       ✓ fastest  +2 zone   A:Z2 B:Z0   "2022 World Cup"  ⇄ turnover
   ...
 112.7s  🏁 FULL TIME   WIN for Alice (decided by goals)
```

---

## The five rules that define the game

1. **Speed is the skill.** Both players answer; the faster correct answer takes +2, the slower +1.
   Wrong costs a zone. The 9-second window is the whole game.
2. **The pitch tells the story.** Six zones, you always attack upward. Reach zone 5 and you get a
   5-second Shooting Chance at difficulty 4–5. Goals are the score.
3. **Language is invisible.** Same question id, per-locale rendering, per-player option shuffle.
   A question is **one database row** with both languages, so the two players cannot diverge.
4. **The server is the only clock.** Answers are judged on server receive time. The client renders
   a countdown; it never decides anything.
5. **The answer key never leaves the server before the reveal.** Enforced by a test that inspects
   every outbound question payload.

## Architecture at a glance

```
Flutter (portrait, 1 thumb)
   │  wss  JSON envelope
   ▼
Edge gateway ──authn, rate limit, shard = hash(matchId) % N
   │
   ▼
Match node ── MatchRoom actor: no timers of its own, advanced by advance(now)
   │            ├── scoring.ts   pure rules  (the rulebook as code)
   │            ├── render.ts    per-locale view  (the answer key is never emitted)
   │            └── token.ts     HMAC binds answer → match/round/player/expiry
   ▼
Redis (queue, presence, snapshots)   PostgreSQL (questions, matches, ratings)
```

The room has **no timers**. `advance(now)` is called by the host loop every 50 ms, and by tests
with synthetic timestamps — which is why a full 90-second match can be simulated in microseconds
and why a crash is recoverable by replay.

---

## Content pipeline

Three commands, in order, all idempotent:

```bash
node db/normalize.mjs        # recompute EN/AR character parity from the actual copy
node db/shuffle-answers.mjs  # spread correct answers across option positions
node db/check-schema.mjs     # ajv strict: is the document shaped correctly?
node db/validate.mjs         # the gate: exits 1 on any fairness violation
```

The validator enforces what a schema cannot:

- `stat_highlow` answers must follow **arithmetically** from the question's own `values`
- emoji clues must be **bidi-isolated** (U+2066…U+2069), or an RTL UI mirrors the clue and the two
  players get different puzzles
- `blur_reveal` assets must be **text-free**, or one language gets a free hint
- EN/AR character parity must stay inside `[0.55, 1.85]`
- publishing requires **Arabic linguist sign-off** (also enforced by a Postgres `CHECK`)
- ±35% regional balance across MENA/African and global content

## Design decisions worth arguing about

| Decision | Alternative | Why this |
|---|---|---|
| One question row, both locales | Separate EN/AR rows | Two rows drift; drift breaks the only claim the game makes |
| Answer as `optionId`, never index | Option index | Options are shuffled per player, so an index is correct for exactly one of them |
| Pitch never flips | Mirror the whole UI | Arabic players would attack downward and every celebration inverts |
| 120 ms jitter grace → both get +2 | Break every tie | At 120 ms we cannot separate skill from network asymmetry |
| Clock floor of 3.5 s per round | Pure time-in-play | Without it, instant answers fit ~19 questions into a half and speed becomes unbounded leverage |
| Anonymous-first auth | Signup wall | Costs >40% of the funnel before the first match |
| No monetization in MVP | Cosmetics/battle pass | Any paid edge voids the fairness thesis |

## What is deliberately missing

Friend lists, chat, tournaments, cosmetics, spectator mode, ads, offline play, bots in ranked.
Each is a real feature; none is needed to prove that a 90-second cross-language duel is fun.

---

## Take it to GitHub

```bash
git remote add origin git@github.com:<you>/grid-and-glory.git
git push -u origin main
```

The first push runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml) — typecheck, 57
tests, schema, bank fairness, Flutter structure. That must be green before anything else.

[`.github/workflows/android.yml`](.github/workflows/android.yml) is manual-triggered and is
the only place an APK gets built, because it needs an x86-64 runner.

**Before making the repo public, add a `LICENSE`.** With no license the default is "all
rights reserved": nobody may legally copy, modify or ship it. That is rarely the intent for
a public repository, and it is a five-second fix — MIT or Apache-2.0 cover most cases.

## Status

| | |
|---|---|
| Spec | Complete and internally consistent |
| Question bank | 54 seeded, validated, pipeline-clean (target 400 at launch) |
| Match engine + gateway | Working, typechecked, 57 tests, real two-client match verified |
| Capacity | Measured: ~1 800 matches/core ceiling, sized to ~600/core for <15 ms p99 |
| Flutter app shell | Written and structurally checked; never compiled (no SDK here) |
| Database | DDL reviewed; not yet applied to a live instance |
| Android build | Signing, manifest and CI all ready. **Not built here** — aarch64 host, and no ARM64 Flutter SDK exists (`RELEASE.md §0`) |
| Play Store | Checklist complete; submission not started |

**Client:** [`app/README.md`](app/README.md) covers `flutter run`, the three layers, and the structural gate.

**Start here:** [`docs/00-product-spec.md`](docs/00-product-spec.md) → [`docs/03-realtime-matchmaking.md`](docs/03-realtime-matchmaking.md) → [`server/src/match-room.ts`](server/src/match-room.ts).
