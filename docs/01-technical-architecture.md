# Technical Architecture

**Status:** v1.0 — MVP architecture
**Scope:** everything needed to run ranked 1v1 cross-language matches at 10k concurrent players.

---

## 1. Stack decision

| Layer | Choice | Why this, not the obvious alternative |
|---|---|---|
| Client | **Flutter 3.32+ (Dart 3.9)** | Single codebase for the two stores; `Directionality` + ARB is the most mature RTL story on mobile; `CustomPainter` gives us the 40%-height pitch at 60 fps without an engine. |
| Pitch rendering | **Flutter `CustomPainter` + `AnimationController`** (Flame optional later) | A 6-zone, 2-avatar scene does not need a game engine. Flame is a 12 MB dependency and an extra render loop; we can adopt it in v2 for character animation without changing the state model. |
| State (client) | **Riverpod 2 + freezed** | Compile-safe DI, testable without `BuildContext`; the match view model is a pure reducer fed by server events. |
| Gateway / realtime | **Node.js 22 LTS + TypeScript, `uWebSockets.js`** | Single-threaded event loop is ideal for timer-driven rooms; ~1.5 µs/message parse at our payload size; horizontal sharding by `matchId`. |
| Room state | **In-process actor, snapshot → Redis** | Match state changes ~2×/s; a DB round-trip per tick is waste. Redis gives crash recovery and cross-node handoff. |
| Matchmaking | **Redis 7 sorted sets + Lua** | Atomic pair-claim; no distributed lock service needed at MVP scale. |
| Durable store | **PostgreSQL 16** | JSONB for question documents + relational integrity for matches/ratings. One store, one backup story. |
| Cache / presence | **Redis 7** | Queue, presence, rate limits, reconnect grace, question-seen TTLs. |
| Auth | **Anonymous device identity → optional Apple/Google link** | A signup wall before the first match is a >40% funnel loss. Anonymous first, upgrade later (required for account-deletion compliance). |
| CDN | **Cloudflare** (R2 for assets) | Blur & Reveal assets are the only heavy payload; signed, short-TTL URLs. |
| Telemetry | **PostHog (self-host later) + structured stdout → Loki** | Product analytics and match forensics are different pipelines; do not merge them. |
| Deploy | **Fly.io or ECS, 2 regions** (`fra` + `dxb`) | `dxb` exists purely for MENA latency; cross-region matchmaking is allowed after 8 s. |

### Rejected alternatives (and the reason, recorded so it is not re-litigated)

- **Python + FastAPI/websockets** — fine for the REST surface, worse tail latency under 5k concurrent
  timer-driven rooms; the scoring core is pure and portable anyway, so this is reversible.
- **Firebase Realtime DB / Firestore for match state** — cannot express server-authoritative
  sub-second timers without Cloud Functions per tick; cost scales with message count, not players.
- **A game engine (Unity/Godot)** — 25–40 MB binary for a quiz UI. Wrong tool.
- **Serverless WS (API Gateway)** — 10-minute connection cap and per-message pricing break 90 s rooms
  at scale, and cold starts are fatal for a 5 s shooting window.

---

## 2. Topology

```
                    ┌──────────── Cloudflare (TLS, WAF, CDN) ────────────┐
                    │                    assets/*.png (signed, 30 s)     │
                    └───────────────┬───────────────────────────────────┘
                                    │ wss
        ┌───────────────────────────┴────────────────────────────┐
        │                     Edge Gateway (Node)                │
        │  authn · ws upgrade · rate limit · region affinity     │
        └───────┬───────────────────────────────┬────────────────┘
                │ SHARD = matchId % N           │
      ┌─────────▼─────────┐          ┌──────────▼────────┐
      │  Match Node A     │          │  Match Node B     │
      │ ┌───────────────┐ │          │ ┌───────────────┐ │
      │ │ Room actor    │ │          │ │ Room actor    │ │
      │ │ (per match)   │ │          │ │               │ │
      │ └───────┬───────┘ │          │ └───────┬───────┘ │
      └─────────┼─────────┘          └─────────┼─────────┘
                │      Redis (queue, presence, snapshots, TTLs)
                │                              │
        ┌───────▼──────────────────────────────▼───────┐
        │ PostgreSQL 16 (primary + read replica)       │
        │ matches · match_rounds · players · questions │
        └──────────────────────────────────────────────┘
```

**Sharding model:** a match lives on exactly one node for its lifetime. Gateway computes
`shard = hash(matchId) % N` and routes; the node owns all timers and state for that match.
No cross-node coordination during play. This is the whole reason the design holds 10k CCU on
a handful of small instances.

**Node capacity (measured, not estimated).** `npm run bench` advances live matches one 50 ms tick
at a time — engine only, no sockets, no JSON, no GC:

| Concurrent matches | mean tick | p95 | p99 | p99 per match |
|---|---|---|---|---|
| 100 | 0.18 ms | 0.40 ms | 3.47 ms | 34.7 µs |
| 400 | 0.38 ms | 0.72 ms | 10.27 ms | 25.7 µs |
| 800 | 0.74 ms | 1.67 ms | 21.98 ms | 27.5 µs |

Cost is linear (~27 µs of p99 per match per tick). A 50 ms tick budget therefore supports
**~1 800 matches/core at 100% CPU** — but a node should never run at 100%.

**Sizing: ~600 matches per core keeps p99 near 15 ms**, i.e. ~1 200 matches on a 2 vCPU node,
with half the CPU left for socket I/O, serialisation and GC. At 800/core the worst tick hit
50.2 ms — one missed deadline, which is exactly what sizing on the *mean* (1.1 µs/match) would
have hidden.

The benchmark starts every match in the same tick, so all rooms transition together — worse than
staggered production traffic, which makes these numbers conservative.

Scale by adding nodes; no rebalancing needed because rooms are ephemeral.

---

## 3. Latency budget

The player experience is `tap → button depresses → result`. Everything between is invisible but budgeted.

| Hop | Budget p95 | Enforcement |
|---|---|---|
| Client input → WS frame sent | 8 ms | Pre-warmed socket, no JSON re-encode |
| Network RTT (same region) | 40 ms | Region affinity at matchmaking |
| Network RTT (cross-region, worst allowed) | 160 ms | Cap: refuse pairing above 190 ms RTT |
| Gateway → match node | 2 ms | Same AZ |
| Server validate + score | 3 ms | Pure functions, no I/O in the hot path |
| Result broadcast | 4 ms | Fan-out to 2 sockets |
| Client render | 16 ms | One frame, `RepaintBoundary` |
| **Total** | **≤ 180 ms** | Matches product target |

**Cross-region fairness.** We do **not** add artificial delay to the faster player (that would reward
distance). Instead: (a) region affinity is tried first for 8 s; (b) the 120 ms jitter grace absorbs the
tail; (c) matches between distant regions are allowed but excluded from ranked Elo (they still count
for the ladder *display*, flagged `crossRegion: true`). Documented because "just delay the fast guy"
is a tempting wrong fix.

---

## 4. Clock synchronisation

The server is the only clock. Clients need it to render a countdown that matches the server's verdict.

```
client                          server
  │  t0 ── ping {c0} ──────────▶ │  serverNow = S
  │  ◀───────── pong {c0, S} ──  │
  │  t1
  │  rtt  = t1 - t0
  │  offset ≈ S + rtt/2 - t1
```

- 5 samples on connect, then 1 every 10 s.
- Offset estimate = **median** of the last 5 samples (median, not mean: one spike must not move the clock).
- Applied as `estimatedServerNow = clientMonotonicNow + offset`.
- Server sends absolute epoch-ms deadlines (`windowEndsAt`), never durations, so a client that joins
  mid-round is still correct.
- **Answers are judged on server receive time.** `clientMs` is retained purely for anti-cheat forensics
  and is never used for fairness. This is the single most important integrity rule in the system.

---

## 5. Question delivery & integrity

1. At match start the server draws a **16-question pool** (`difficulty` curve per `00-product-spec.md §3.2`),
   seeded deterministically from `matchId` so any match can be reconstructed exactly.
2. Per round, the server sends `round.question` containing prompt + options **for that player's locale
   only**, shuffled per player, plus a `questionToken`.
3. `questionToken = base64url(HMAC-SHA256(key, matchId|roundNo|questionId|answerOptionId|exp))`.
   The token binds the round to the answer without revealing it. It is verified on submit and
   discarded at reveal. This makes "guess the token" attacks useless and lets the server detect
   forged answer payloads from modified clients.
4. **The correct answer never leaves the server before `round.reveal`.** A rooted device inspecting
   memory during the question window finds nothing.
5. **Blur & Reveal assets** are served as signed URLs with a 30 s TTL, issued inside `round.question`.
   A client cannot pre-download the next round's image, which would defeat the format.
6. The full bank is **never** bundled into the app binary. Offline play is a separate, explicitly
   smaller subset if it is ever added.

### Anti-cheat controls (MVP)

| Threat | Control |
|---|---|
| Modified client reads answer | Answer absent from wire until reveal (§5.4) |
| Automation / scripted answers | Sub-250 ms correct-answer rate > 3σ → shadow-flag, manual review |
| Answer replay / duplicate submit | Idempotency on `(matchId, roundNo, playerId)`; first write wins |
| Token forgery | HMAC + `exp` = `windowEndsAt + 2 s` |
| Pre-fetching next image | Signed 30 s asset URLs (§5.5) |
| Multi-accounting to farm rating | Device fingerprint + ranked requires ≥ 5 completed matches |
| Time manipulation | Client clock never authority (§4) |
| Question-bank scraping | Never shipped; per-request rotation; per-account serve caps |

**Explicitly not solved in MVP:** real-time cheating via a second device + human lookups. It is
undetectable at this scale and the economy does not justify it. Revisit if ranked leaderboards
ever carry real prizes.

---

## 6. Failure modes

| Failure | Behaviour | Player impact |
|---|---|---|
| Match node crash | Redis snapshot restore on another node; players re-`state.sync` | ≤ 4 s freeze, match continues |
| Redis unavailable | New matchmaking paused; in-flight matches continue (state is in-memory) | Cannot start new match |
| Postgres unavailable | Matches complete; results buffered to disk queue and replayed | None during play; ranking delayed |
| Player disconnect | 25 s grace, opponent sees "opponent reconnecting"; missed rounds = no answer | Forfeit after grace |
| Both disconnect | Match voided, no rating change | None |
| Clock drift > 2 s | Client re-syncs on every round intro (deadline included) | None |
| Asset CDN slow | Round intro shows skeleton; blur images pre-warmed at intro | Slight reveal jank |

**Idempotent result write:** `matches` upsert keyed by `match_id` with `state='final'`; a duplicate
finalisation is a no-op. Ranking is applied by a single transaction guarded on `finalised_at IS NULL`.

---

## 7. Observability

Per match, one structured JSON line per state transition (sampled 100% for anomalous matches):

```json
{"t":"2026-11-10T09:14:22.041Z","lvl":"info","ev":"round.resolve","matchId":"m_01J...",
 "round":4,"half":1,"qId":"q_mc_ucl_0007","outcome":{"A":"correct","B":"wrong"},
 "dtMs":842,"delta":{"A":[2,3],"B":[-1,1]},"lag":{"A":41,"B":58}}
```

Dashboards (required before soft launch):

- **Match funnel:** queued → paired → started → completed → rematched, split by locale pair (EN-EN, AR-AR, EN-AR).
- **Latency:** p50/p95/p99 answer ack, by region pair.
- **Fairness:** win-rate by locale, by locale pair, by region distance; alert if `|Δ| > 5 pts` over 500 matches.
- **Content health:** correct-rate per question (auto-retire extremes), unanswered rate, format performance.
- **Integrity:** late-answer rate, sub-250 ms correct rate, token-verify failures, duplicate submits.

---

## 8. Security & compliance

- TLS 1.3 only; HSTS; cert pinning on the WS host (mobile).
- JWT (15 min) + refresh token in `flutter_secure_storage` (Keychain / Android Keystore).
- No PII required to play. Display name is a generated pseudonym; changeable, moderated.
- **Account deletion** is an in-app flow (Google Play requirement), soft-delete + 30-day purge.
- GDPR/CCPA data export endpoint; no ad SDK in MVP → dramatically smaller Data Safety form.
- COPPA: age gate at first launch; under-13 → no chat-adjacent features, no ranked.
- Rate limits: 5 WS connects/min/IP, 30 answers/min/player, 3 match starts/min/player.

---

## 9. Cost shape (10k CCU, monthly, order of magnitude)

| Item | Est. |
|---|---|
| 4 × 2 vCPU match nodes | $120 |
| Redis (managed, 1 GB HA) | $60 |
| Postgres (managed, 2 vCPU, 100 GB) | $110 |
| Egress / CDN (assets, ~40 GB) | $35 |
| PostHog self-host (small VM) | $25 |
| **Total** | **≈ $350/mo** |

The dominant cost risk is not compute, it is **content authoring + Arabic linguist review**.
Budget it as a line item, not an afterthought.

---

**Related:** `03-realtime-matchmaking.md` (protocol + state machine) · `02-database-schema.md` (persistence)
