# Real-Time Matchmaking & State Machine

**Implementation:** [`server/src/matchmaking.ts`](../server/src/matchmaking.ts) · [`server/src/match-room.ts`](../server/src/match-room.ts) · [`server/src/scoring.ts`](../server/src/scoring.ts)
**Run it:** `node server/src/demo.ts` prints a full match play-by-play.

---

## 1. Transport

| Property | Value |
|---|---|
| Protocol | WebSocket over TLS 1.3 (`wss://`) |
| Encoding | JSON for MVP; the envelope is versioned so MessagePack is a drop-in later |
| Server | Node 22 LTS + TypeScript, `uWebSockets.js` |
| Heartbeat | client `ping` every 10 s; server closes at 3 missed |
| Max frame | 16 KB inbound (a question view is ~2 KB; anything larger is abuse) |
| Reconnect | 25 s grace, resume by `matchId` + player token |

### Envelope

```jsonc
{ "v": 1, "type": "round.answer", "seq": 42, "ts": 1770000000123, "payload": { } }
```

`seq` is per-connection monotonic and used only to detect dropped/duplicated frames.
`ts` is the client clock and is **advisory** — see §6.

## 2. Protocol catalogue

### Client → server

| Type | Payload | Notes |
|---|---|---|
| `hello` | `{deviceId, locale, region, appVersion}` | Anonymous identity; server issues a JWT |
| `queue.join` | `{}` | Idempotent: double-tap cannot double-queue |
| `queue.leave` | `{}` | |
| `match.ready` | `{matchId}` | Client has loaded the asset bundle |
| `round.answer` | `{token, optionId, clientMs}` | **The only competitive input** |
| `emote` | `{id}` | 4 canned reactions, rate-limited to 1/3 s |
| `ping` | `{c0}` | Clock sync |

### Server → client

| Type | Payload | When |
|---|---|---|
| `queue.joined` | `{ticket, estimateMs}` | Enqueued |
| `match.found` | `{matchId, opponent, serverNow, regionPair}` | Paired |
| `match.start` | `{half, halfMs, you, opponent, zones, goals}` | Kickoff |
| `round.intro` | `{roundNo, half, halfRemainingMs, windowMs, serverNow}` | 1 s before the question |
| `round.preload` | `{assetUrl}` | Signed URL, for `blur_reveal` only |
| `round.question` | `{roundNo, token, windowEndsAt, view, zones, possession}` | Window opens |
| `round.answer_ack` | `{receivedAt, windowEndsAt, duplicate?}` | Your answer landed |
| `round.opponent_answered` | `{}` | **That** they answered — never what |
| `round.reveal` | `{correctOptionId, correctOptionText, explainer, delta, zone, outcome, fastest, opponentOutcome, …}` | Window closed |
| `shoot.question` | `{shooterId, youAreShooting, token, windowEndsAt, view, difficulty}` | Zone 5 reached |
| `shoot.reveal` | `{scored, correctOptionId, explainer, goals, zones}` | Shot resolved |
| `match.half` | `{goals, zones, stats, opponentStats}` | 45 s |
| `match.second_half` | `{halfMs, zones, goals, possession}` | After half-time |
| `match.end` | `{outcome, decidedBy, goals, zones, stats, ratingDelta}` | Full time |
| `state.sync` | full snapshot | Reconnect |
| `opponent.connection` | `{connected, graceMs}` | Opponent dropped / returned |
| `error` | `{code, reason}` | `BAD_TOKEN`, `TOKEN_MISMATCH`, `RATE_LIMITED` |

> **`round.question` never contains the answer.** Neither does `shoot.question`. The key appears
> for the first time in `round.reveal`. This is verified by a test:
> [`server/test/match.test.ts`](../server/test/match.test.ts) asserts that no question payload
> contains `answerOptionId` or `correctOptionId`.

## 3. Matchmaking loop

```
EVERY 250ms:

  pairs = []

  for each player P in queue, ordered by joined_at ASC:      # nobody is jumped
      if P already paired: continue

      best = null; best_cost = ∞
      for each candidate C in queue where C ≠ P and C not paired:
          gap     = |P.rating - C.rating|
          windowP = 150 + floor(wait(P) / 2s) * 75            # widens while waiting
          windowC = 150 + floor(wait(C) / 2s) * 75
          allowed = min(windowP, windowC)                     # BOTH must accept the gap

          if gap > allowed: continue
          if max(P.rtt, C.rtt) > 190ms: continue              # hard latency ceiling
          if P.region ≠ C.region and min(wait(P), wait(C)) < 8s: continue

          # Lower is better. Rating accuracy dominates; latency is second;
          # waiting is a discount so the oldest ticket is never starved.
          cost = gap*1.0 + maxRtt*0.35 + (sameRegion ? 0 : 180) - min(wait, 20s)*0.03

          if cost < best_cost: best, best_cost = C, cost

      if best ≠ null:
          pair(P, best); mark both paired

  for each pair: create match, emit match.found to both, remove tickets
```

Four rules, each guarding a specific failure:

1. **`allowed = min(windowP, windowC)`** — using the *wider* window lets a patient player get
   matched two tiers away while the newcomer gets sandbagged. Both must consent.
2. **Locale never appears in the predicate.** A queue that groups by language halves the pool and
   deletes the product thesis. The only cost of cross-language play is rendering, which is free.
3. **`max RTT` not `avg`** — if one side has 180 ms and the other has 30 ms, the match must survive
   180 ms. Averaging hides exactly the player who will have a bad time.
4. **Wait discount, not wait priority** — old tickets become *cheaper to pair*, not *first in line*.
   Strict FIFO starves whoever is left when the queue is thin and the population is uneven.

### Redis layout

```
queue:{region}:{mmrBucket}        ZSET  score = joinedAt, member = ticket JSON
queue:global                      ZSET  fallback
match-claim:{playerId}            STRING  NX EX 10   ← the real lock
presence:{playerId}               HASH   {node, connId, lastSeen}
```

The atomic claim is mandatory across nodes: `ZPOPMIN` is atomic, but a player whose ticket exists
in both a regional and the global set can be popped twice. `SET NX` on `match-claim:{playerId}`
is what makes "consumed at most once" true. The full Lua contract is documented in the source.

## 4. Match state machine

```
                        ┌─────────────┐
        match.start ───▶│ round_intro │◀──────────────┐
                        └──────┬──────┘               │
                        +1000ms│                      │
                        ┌──────▼───────┐              │
                        │ question_open│              │
                        └──────┬───────┘              │
              both answered OR │ +windowMs            │
                        ┌──────▼───────┐              │
                        │ round_reveal │              │
                        └──────┬───────┘              │
                        +1400ms│                      │
                               │                      │
                    ┌──────────┴──────────┐           │
                    │                     │           │
              zone==5 & cooldown ok   otherwise ──────┘
                    │                     │
                    │              half clock <= 0 ?
                    │                │        │
        ┌───────────▼──────┐   half 1 │        │ half 2
        │ shooting_chance  │          ▼        ▼
        │  (clock frozen)  │   ┌───────────┐ ┌──────┐
        └────────┬─────────┘   │ half_time │ │ended │
                 │ resolved    └─────┬─────┘ └──────┘
        ┌────────▼────────┐  +6000ms │
        │   shot_reveal   │          ▼
        │  (clock frozen) │   ┌─────────────┐
        └────────┬────────┘   │second_half  │
                 │ +2200ms    └──────┬──────┘
                 └───────────────────┘  (returns to round_intro)
```

| Transition | Trigger | Clock effect |
|---|---|---|
| `round_intro → question_open` | +1000 ms | −1000 ms |
| `question_open → round_reveal` | both answered, or window expiry | `−max(elapsed, 3500 ms)` |
| `round_reveal → (shot \| half \| next)` | +1400 ms | −1400 ms |
| `shooting_chance → shot_reveal` | shooter answers, or +5000 ms | **frozen** |
| `shot_reveal → (half \| next)` | +2200 ms | **frozen** |
| `half_time → second_half` | +6000 ms | reset to 45 000 |

**Why the room owns no timers.** `MatchRoom.advance(now)` takes `now` as an argument. The host
loop calls it every 50 ms; a test calls it with synthetic timestamps and plays a whole match in
microseconds. The state machine cannot drift from its own clock because it does not have one.

## 5. Round resolution

```
FUNCTION resolveRound(question, answers, windowOpensAt, windowEndsAt):

  FOR EACH player IN [A, B]:
      answer = answers[player]

      IF answer IS NULL:
          outcome = NO_ANSWER; delta = -1
      ELSE IF answer.receivedAt > windowEndsAt + 150ms:
          outcome = NO_ANSWER; delta = -1; late = true        # recorded, not counted
      ELSE IF answer.optionId ≠ question.answerOptionId:
          outcome = WRONG; delta = -1
      ELSE:
          outcome = CORRECT; delta = +1 (provisional)
          late = answer.receivedAt > windowEndsAt

  eligible = [correct answers that are NOT late]              # late never earns the bonus
  SORT eligible BY receivedAt ASC

  IF len(eligible) == 1:
      eligible[0].delta = +2
  ELSE IF len(eligible) == 2:
      IF eligible[1].receivedAt - eligible[0].receivedAt < 120ms:
          both.delta = +2                                     # jitter grace
      ELSE:
          eligible[0].delta = +2
          eligible[1].delta = +1

  FOR EACH player: player.zone = clamp(player.zone + delta, 0, 5)
```

Three subtleties that are easy to get wrong and are covered by tests:

- **Lateness is not wrongness.** A correct answer at window+100 ms scores a zone. It just cannot be
  the fastest, because it arrived after the clock the opponent was racing.
- **Jitter grace is 120 ms, and it makes *both* players fastest.** At that resolution we cannot
  distinguish skill from network asymmetry, and a fair game that randomly punishes the loser of a
  coin flip feels rigged even when it is not.
- **The comparison is `receivedAt` on the server.** `clientMs` is never used for scoring — it is
  retained only so an anomalous answer can be investigated after the fact.

## 6. Clock synchronisation

```
client                          server
  │  t0 ── ping {c0} ─────────▶  │  S = serverNow()
  │  ◀──────── pong {c0, S} ──   │
  │  t1
  │  rtt    = t1 - t0
  │  offset = S + rtt/2 - t1
```

- 5 samples on connect, then 1 every 10 s.
- **Median** of the last 5, not mean: one GC pause must not move the clock.
- The server sends absolute deadlines (`windowEndsAt`), never durations, so a client that joins a
  round late still computes the correct remaining time.
- A client whose estimate is off by more than 2 s is asked to resync at the next intro.

**The server does not trust any client timestamp for anything competitive.** Clock sync exists so
the countdown the player sees matches the verdict they receive — not for judging speed.

## 7. Host loop

```ts
// one process, one shard, several thousand rooms
setInterval(() => {
  const now = Date.now();

  for (const room of rooms.values()) {
    let out: Outbound[];
    try {
      out = room.advance(now);
    } catch (err) {
      // A throwing room must never take down the node.
      log.error({ matchId: room.matchId, err }, "room.advance failed");
      room.fail(now);           // emits match.end / void, frees the slot
      continue;
    }
    for (const env of out) send(env.to, env.type, env.payload);
    if (room.isFinished) rooms.delete(room.matchId);
  }
}, 50);
```

50 ms tick: worst-case added latency 50 ms, well inside the 180 ms budget, and at 1 200 rooms that
is ~1 200 trivial state checks per tick — a fraction of a millisecond.

**Sharding.** `shard = hash(matchId) % N`. A match lives on one node for life. No cross-node
coordination during play; scale by adding nodes because rooms are ephemeral and need no rebalancing.

## 8. Failure & recovery

| Event | Handling |
|---|---|
| Player disconnects | Opponent sees "reconnecting" + 25 s grace. Missed rounds are `NO_ANSWER`. |
| Player reconnects | `state.sync` with zone/goals/clock. **Deadline unchanged** — reconnecting never buys time. |
| Both disconnect | Match voided, no rating change. |
| Grace expires | Forfeit: opponent wins, `decidedBy = 'forfeit'`. |
| Node crash | Room snapshot in Redis replayed on a healthy node; players re-`state.sync`. |
| Duplicate result write | `UPDATE ... WHERE finalised_at IS NULL` — second write updates 0 rows. |
| Redis down | New matchmaking paused; in-flight matches unaffected (state is in memory). |

## 9. Anti-cheat, summarised

| Threat | Control | Where |
|---|---|---|
| Read the answer from the wire | Key withheld until reveal | `render.ts`, tested |
| Forge an answer for another question | HMAC token bound to match/round/player/expiry | `token.ts` |
| Replay a submit | Idempotent `(match×round×player)`, first write wins | `match-room.ts` |
| Tamper with the clock | Server `receivedAt` is the only authority | `scoring.ts` |
| Scrape the bank | Never shipped; CDN assets signed 30 s | `bank-loader.ts`, CDN |
| Pre-fetch blur images | Signed URL issued inside `round.question` | `match-room.ts` |
| Farm ranked on a new account | Ranked requires 5 completed matches | matchmaking |
| Bot-speed answering | Sub-250 ms correct rate > 3σ → shadow-flag | analytics |

**Not solved:** a human with a second device. Undetectable at this scale, and the MVP ladder carries
nothing worth the effort. Revisit if ranked ever carries prizes.

---

## 10. Running it

The protocol is implemented, not just specified. Four files, one responsibility each:

| File | Responsibility |
|---|---|
| `server/src/gateway.ts` | Protocol, sessions, queue, match lifecycle. **No sockets.** |
| `server/src/server.ts` | The only file that imports `ws`. Converts sockets → `Connection`. |
| `server/src/index.ts` | Process bootstrap: env, health endpoint, SIGTERM drain. |
| `server/src/smoke.ts` | Two real clients playing a real match over the wire. |

```bash
# terminal 1
npm run serve
# → Grid & Glory gateway listening on ws://0.0.0.0:8080/ws (54 questions, 8 shot-pool)

curl localhost:8080/healthz
# {"ok":true,"connections":0,"sessions":0,"queued":0,"liveMatches":0,"matchesStarted":0}

# terminal 2 — an English client and an Arabic client, one match
npm run smoke
```

```
11:12:07.411  EN   connected as Striker-1984 (ltr)
11:12:07.421  AR   connected as Winger-6433 (rtl)
11:12:07.468  EN   matched vs Winger-6433 [ar] match=m_mwalbrj0_i5_1i7_2
11:12:40.398  EN   second half
11:13:06.114  AR   R8 correct (2) → zone 5
11:13:08.212  AR   🧤 saved
11:13:10.434  AR   FULL TIME win (zone)
  finished: EN(16 rounds), AR(17 rounds)
```

Both clients answer through **both halves** — a regression this smoke test caught, when half two
used to re-draw half one's questions and the rule "never twice in one match" was quietly broken.

### Why the transport is a seam

`Gateway.handleFrame(conn, raw)` takes a `Connection`, and `Gateway.tick(now)` takes the clock.
Neither knows what a socket is. That is what makes these tests possible:

| Test | Mechanism | Duration |
|---|---|---|
| Full two-player match over the protocol | `MemoryConnection` + virtual clock | ~50 ms |
| Reconnect inside/outside the grace window | Same, with a second connection and a token | ~5 ms |
| Rate limiting, forged tokens, queue ghosts | Same | ~2 ms |
| Real HTTP upgrade + JSON framing | Actual `ws` server on an ephemeral port | ~300 ms |

A 90-second match that can only be tested by waiting 90 seconds is a match that stops being
tested. The virtual clock is not a testing convenience bolted on afterwards — it is the reason
`MatchRoom` was written without timers in the first place.

### Adding a transport feature

If a new message needs to reach a player, it goes:

```
MatchRoom emits Outbound { to: playerId, type, payload }
        ↓
Gateway.dispatch resolves playerId → Connection (or fans out on "all")
        ↓
server.ts serialises to JSON and writes to the socket
```

`Gateway` never constructs a payload that `MatchRoom` did not produce. That invariant is what keeps
the client honest: it cannot be told anything the referee did not decide.
