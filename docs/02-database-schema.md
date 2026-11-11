# Database Schema

**Engine:** PostgreSQL 16 · **DDL:** [`db/schema/migrations.sql`](../db/schema/migrations.sql) · **Content contract:** [`db/schema/question-bank.schema.json`](../db/schema/question-bank.schema.json)

---

## 1. The one decision everything else follows

> **A question is one row containing both languages.**

There is no `questions_en` and no `questions_ar`. There is no `locale` column on a question.
A question has `prompt.en`, `prompt.ar`, `explainer.en`, `explainer.ar` — inside a single JSONB
document, with `answerOptionId` as a language-independent key.

This is the load-bearing choice for cross-language matchmaking:

| If you split by locale | Consequence |
|---|---|
| Two rows per question | They drift. One gets fixed, the other does not. |
| Answer index instead of id | Option shuffling is per-player, so index ≠ answer for one of them. |
| Difficulty per locale | Riyad Mahrez is "easy" on one side of the Mediterranean and "hard" on the other — now the match is unfair and nobody can prove it. |
| Separate pools | The players are not playing the same game. The premise is dead. |

One row makes divergence **structurally impossible**, not merely discouraged. The Arabic
linguist's sign-off (`ar_verified_by`) is a `CHECK` constraint on publishing, so a script cannot
ship an unverified Arabic question either.

## 2. Shape

```
seasons ─┬─< player_ratings >─ players ─< player_identities
         │                        │
         │                        ├─< player_settings
         │                        └─< question_seen >─ questions ─< question_versions
         │                                              │
         └─< matches ─< match_players >────────────────┘
                    ├─< match_rounds >─── question_id
                    └─< match_answers
```

`analytics_events` sits outside the graph: partitioned by month, written through a queue, never
joined in a request path.

## 3. JSONB or column?

Promoting everything to columns would mean ~30 columns per format. Promoting nothing would mean
`WHERE (doc->>'difficulty')::int = 3` scans and no index. The split is by **access pattern**:

| Lives in JSONB | Lives in a column | Why |
|---|---|---|
| prompt, options, explainer, formatData | — | Never queried, always rendered whole |
| — | `format`, `difficulty`, `region` | The three axes of question selection |
| — | `status` | Every read is `status = 'published'` |
| — | `answer_option_id` | Scoring must not parse JSON to grade a round |
| — | `checksum` | Duplicate detection across a 5 000-question bank |
| — | `ar_verified_by` | Has to be enforceable by `CHECK`, not by convention |

Shadow columns are kept honest by `CHECK` constraints that recompute from the document:

```sql
CONSTRAINT questions_format_matches_doc CHECK (doc ->> 'format' = format),
CONSTRAINT questions_answer_matches     CHECK (doc ->> 'answerOptionId' = answer_option_id)
```

A promoted column that disagrees with its document fails the write. No silent drift.

## 4. Table reference

### Content

| Table | Purpose | Growth |
|---|---|---|
| `questions` | Canonical bilingual question. One row per question. | Thousands, human-paced |
| `question_versions` | Immutable copy of every published revision | ~5× questions |
| `question_seen` | Anti-repetition ledger, 30-day retention | Players × matches |

`question_versions` exists because a disputed match must be replayable against **the text the
players actually saw**. `match_rounds.question_version` points into it.

### Players

| Table | Purpose |
|---|---|
| `players` | Identity, locale preference, region, soft-delete marker |
| `player_identities` | `(provider, subject)` → player. Guest first, upgrade later |
| `player_settings` | Locale, numeral style, haptics, reduced motion |
| `player_ratings` | Rating per season, with Glicko-2 fields pre-provisioned |

`player_identities` is separate from `players` so a guest can become a Google account without a
data migration, and so one human cannot accidentally hold two ranked profiles on one device.

### Matches

| Table | Purpose |
|---|---|
| `matches` | Header: who, when, result, finalisation marker |
| `match_players | Per-player line: goals, zone, accuracy, rating delta |
| `match_rounds` | Every question served, with version and window timestamps |
| `match_answers` | Every answer, with server receive time and lateness flag |

All four are **append-only**. The only mutation permitted is stamping `finalised_at`.

## 5. The two queries that matter

### 5.1 Drawing a match pool

Server-side, at match start. Not per round — the pool is drawn once, then walked.

```sql
WITH candidate AS (
  SELECT q.id, q.format, q.difficulty,
         q.doc -> 'prompt' ->> 'en' AS prompt_en,
         q.doc -> 'prompt' ->> 'ar' AS prompt_ar,
         q.answer_option_id, q.version, q.doc
  FROM questions q
  WHERE q.status = 'published'
    AND q.difficulty BETWEEN $1 AND $2
    -- Never serve a question either player saw in the last 30 days.
    AND NOT EXISTS (
      SELECT 1 FROM question_seen s
      WHERE s.question_id = q.id AND s.player_id = ANY($3::uuid[])
    )
  -- Prefer the region the match is "about" without excluding global content.
  ORDER BY (q.region = $4) DESC, random()
  LIMIT $5
)
SELECT * FROM candidate;
```

Two details that are easy to get wrong:

- **`ORDER BY (region = $4) DESC, random()`** biases toward the match's region but never filters.
  Filtering by region gives a MENA player a bank of 200 questions and a global player a bank of 4 000.
- **The `NOT EXISTS` is a correctness requirement, not a nicety.** Trivia dies the moment a player
  recognises the question, and a 90-second match makes repetition extremely visible.

### 5.2 Finalising a match (idempotent)

The rating write is the only place where a duplicate delivery would corrupt the ladder, so the
guard is in the `WHERE` clause rather than in application logic:

```sql
BEGIN;

UPDATE matches
SET state = 'final', ended_at = $2, finalised_at = now(),
    winner_id = $3, decided_by = $4
WHERE id = $1 AND finalised_at IS NULL;      -- ← the idempotency guard

-- Only one writer can win this branch. A duplicate result message updates 0 rows.
-- If rowcount = 0, roll back and return "already finalised".

UPDATE player_ratings r
SET rating = r.rating + mp.rating_delta,
    matches_played = r.matches_played + 1,
    updated_at = now()
FROM match_players mp
WHERE mp.match_id = $1
  AND mp.player_id = r.player_id
  AND r.season_id = $5;

COMMIT;
```

`matches_unfinalised_idx` (partial, `WHERE finalised_at IS NULL`) keeps the recovery sweeper cheap:
it finds orphaned live matches after a node crash without scanning history.

## 6. A question document, in full

```jsonc
{
  "id": "q_stat_wcgoals",
  "format": "stat_highlow",
  "difficulty": 4,
  "region": "GLOBAL",
  "prompt": {
    "en": "Who scored more World Cup goals?",
    "ar": "من سجّل أهدافاً أكثر في كأس العالم؟"
  },
  "options": [
    { "id": "opt_equal", "en": "Equal", "ar": "متساويان" },
    { "id": "opt_a", "en": "Miroslav Klose", "ar": "ميروسلاف كلوزه" },
    { "id": "opt_b", "en": "Ronaldo Nazário", "ar": "رونالدو نازاريو" }
  ],
  "answerOptionId": "opt_a",
  "formatData": {
    "statLabel": { "en": "World Cup goals", "ar": "أهداف كأس العالم" },
    "entityA": "p_klose",
    "entityB": "p_r9",
    "values": { "A": 16, "B": 15 },     // ← never sent to a client before reveal
    "direction": "higher",
    "unit": { "en": "goals", "ar": "هدفاً" }
  },
  "explainer": {
    "en": "Klose scored 16 across four World Cups; Ronaldo Nazário scored 15.",
    "ar": "سجّل كلوزه 16 هدفاً في أربع نسخ، وسجّل رونالدو نازاريو 15."
  },
  "stats": { "dataAsOf": "2026-06-01" },
  "localization": { "enChars": 58, "arChars": 55, "parityRatio": 0.948, "verifiedBy": "ar-linguist-01" },
  "authoring": { "status": "published", "version": 1, "updatedAt": "2026-11-10T09:00:00.000Z" }
}
```

Note what is **not** here: no `locale` field, no translated option index, no per-language
difficulty. `values` is present in the document (it must be, for the reveal and for the validator
to prove the answer arithmetically) but the server strips it in `render.ts` before sending.

## 7. Retention & operations

| Data | Retention | Mechanism |
|---|---|---|
| `analytics_events` | 13 months | Monthly partitions; `DROP PARTITION` |
| `question_seen` | 30 days | Nightly `DELETE ... WHERE served_at < now() - interval '30 days'` |
| `match_answers` / `match_rounds` | 18 months | Archive to object storage, then delete |
| `players` (soft-deleted) | 30 days | Purge job, then hard delete |
| `reports` | 24 months | Compliance |

**Backups:** PITR with 7-day WAL retention, nightly logical dump to cold storage, quarterly
restore drill. A backup nobody has restored is not a backup.

**Migrations:** forward-only, numbered, applied by a job that takes an advisory lock. Never edit an
applied migration; the schema is the contract. Expand/contract for breaking changes (add column →
dual-write → backfill → switch reads → drop old), because the mobile client is always a version
behind and never updates on your schedule.

## 8. Index rationale

| Index | Serves |
|---|---|
| `questions_pool_idx` | The pool draw: `status, region, difficulty, format` |
| `questions_tags_idx` (GIN) | Editorial tooling and "more like this" |
| `questions_checksum_uidx` | Duplicate detection on import |
| `question_seen` PK | The anti-repetition `NOT EXISTS` — this is on the hot path |
| `match_players_player_idx` | "My recent matches" and rating history |
| `matches_unfinalised_idx` | Crash recovery sweeper |
| `question_seen_purge_idx` | The nightly delete |

The pool draw is the only query on the critical path (it runs once per match, ~once per 3 s per
node). Everything else is offline or per-request.
