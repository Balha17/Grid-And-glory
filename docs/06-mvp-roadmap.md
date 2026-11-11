# MVP Roadmap — 4 Weeks to Closed Testing

**Assumed team:** 1 Flutter dev · 1 backend dev · 1 designer (part-time) · 1 Arabic linguist (part-time) · 1 PM/QA (shared)
**Assumption:** the specification in this repo is the contract. Scope changes go through the cut list (§7), not through silent renegotiation.
**Target:** an AAB in **closed testing** on day 20, production after the 14-day test window.

---

## 1. The shape of the four weeks

```
Week 1  ── FOUNDATIONS ──────── one match vs a bot, both locales, end to end
Week 2  ── REAL MULTIPLAYER ─── two humans, EN vs AR, all five formats
Week 3  ── POLISH & LOCALIZE ── RTL audit, a11y, telemetry, load test
Week 4  ── HARDEN & SHIP ────── store assets, compliance, closed testing
                                   │
                    14-day closed test (12 testers)
                                   │
                    production 20% → 100% rollout
```

Each week ends with a **demoable artifact**, not a status report. If Friday's demo does not run on
a physical mid-tier Android device in both languages, the week failed.

---

## 2. Week 1 — Foundations

**Goal:** two phones on the same Wi-Fi, one English and one Arabic, play a complete 90-second
match against a scripted opponent — server-authoritative, with the real pitch and the real quiz card.

| Day | Work | Owner | Done when |
|---|---|---|---|
| 1 | Repo, CI (lint, `node db/validate.mjs`, server tests), staging env, bundle IDs, branch protection | All | CI is red on a deliberately broken question |
| 1 | Package IDs: `gg.gridandglory.app` (Android) / `gg.gridandglory.app` (iOS) | Backend | Reserved in both consoles |
| 2 | Anonymous auth: device id → JWT, refresh, secure storage | Backend | Cold start with no account reaches Home in < 1.8 s |
| 2 | Locale shell: prefs preload, `Directionality`, ARB files, Home with instant toggle | Flutter | Toggle flips the whole Home screen with no reload and no flash |
| 3 | WS gateway: upgrade, heartbeat, envelope, error codes, rate limits | Backend | 1 000 idle sockets per node without memory growth |
| 3 | `MatchRoom` wired to the gateway; `advance(now)` loop at 50 ms | Backend | A room plays itself against a bot through the real socket |
| 4 | Reducer + `MatchScreen` skeleton: 40/60, HUD, answer buttons | Flutter | A full match is playable on device |
| 4 | Scoring tests, match simulation test, matchmaking tests green | Backend | `node server/test/*.test.ts` all pass |
| 5 | `PitchViewport` painter, zone animation, avatars, possession | Flutter | 60 fps on a 4 GB Android device (DevTools) |
| 5 | Play-by-play demo reviewed against the product spec | PM | A rules disagreement is caught here, not in month 2 |

**Exit criteria**
- [ ] Complete match on two physical devices, one in `en`, one in `ar`
- [ ] The Arabic build renders RTL with the pitch attacking **upward**
- [ ] Answer key never on the wire (test-enforced)
- [ ] No layout overflow at 200% text scale on the Home and Match screens

**Known risk this week:** the 40/60 split is easy to get wrong under `SafeArea` on devices with
large notches. Compute from `constraints.maxHeight` inside `SafeArea`, never from
`MediaQuery.size.height`.

---

## 3. Week 2 — Real Multiplayer and Content

**Goal:** two strangers, one English and one Arabic, matched by an actual queue, playing all five
question formats, with reconnect and forfeit behaving correctly.

| Day | Work | Owner | Done when |
|---|---|---|---|
| 6 | Redis queue, pairing loop, `match-claim` atomicity, region affinity | Backend | Two different locales pair in < 6 s on staging |
| 6 | Matchmaking screen: searching, found, opponent card, cancel | Flutter | Cancel actually removes the ticket |
| 7 | Reconnect (`state.sync`), 25 s grace, forfeit, void-both | Backend | Kill the app mid-round; the match resumes with the same deadline |
| 7 | `opponent.connection` UI, reconnecting banner | Flutter | Opponent sees "25 s to return", not a frozen screen |
| 8 | **Content: 300 published questions**, 35% MENA/African minimum, all passing the validator | Content + linguist | `node db/validate.mjs` passes with `published: 300` |
| 8 | Arabic linguistics review pass; `verifiedBy` stamped | Linguist | 0 questions published without AR sign-off (DB `CHECK` enforces it) |
| 9 | Format UIs: career path chips, emoji reveal, blur & reveal, stat high/low | Flutter | Each format is playable and readable in both locales |
| 9 | Shooting Chance: 5 s, clock frozen, goal/save states | Both | Reaching zone 5 triggers the interrupt and the clock does not move |
| 10 | Half-time card, second half, result screen, rating delta | Flutter | Full match reads as a football match, not a quiz |
| 10 | Idempotent result write + rating transaction | Backend | A duplicated result message changes the rating once |

**Exit criteria**
- [ ] Ten consecutive live matches between two real devices with no desync
- [ ] All five formats served at least once in a match
- [ ] Reconnect inside grace resumes; outside grace forfeits
- [ ] Rating is applied exactly once per match under duplicate delivery

**Known risk this week:** content is the schedule killer, not code. 300 questions is
~10 hours of authoring **plus** ~6 hours of Arabic review. Start on day 1, in parallel with
engineering, or week 2 ends with a finished engine and nothing to ask.

---

## 4. Week 3 — Polish, Localization, Telemetry

**Goal:** the build stops feeling like a prototype, and the locale fairness metric is live.

| Day | Work | Owner | Done when |
|---|---|---|---|
| 11 | Motion pass: zone advance, goal, save, reveal stamp; haptics | Designer + Flutter | Every state change has a 420–900 ms beat, none exceed it |
| 11 | Reduced-motion path | Flutter | OS "remove animations" removes movement, keeps information |
| 12 | Full RTL audit against `04-ui-ux-spec.md §5` — every screen, both directions | Designer + linguist | No `left:`/`right:` in `lib/`; directional icons flip |
| 12 | Golden tests: 2 locales × 2 directions × 2 text scales × 2 screen sizes | Flutter | 16 goldens, all reviewed by a human |
| 13 | Accessibility: semantics labels, focus order, colour-blind check | Flutter | TalkBack reads a full round coherently |
| 13 | Error states: offline, wide search, opponent left, voided match | Flutter | Every error state has an Arabic string, not an English fallback |
| 14 | Analytics: match funnel, latency, **locale win-rate**, content health | Backend | Dashboard shows EN vs AR win rate over the last 500 matches |
| 14 | Crash reporting + structured server logs with `matchId` correlation | Backend | One match can be reconstructed from logs alone |
| 15 | Load test: 500 concurrent matches | Backend | p95 answer→ack < 180 ms; no tick jitter > 50 ms |

**Exit criteria**
- [ ] p95 answer→ack ≤ 180 ms at 500 concurrent matches
- [ ] Locale win-rate delta visible and < 8 points on staging data
- [ ] Zero layout overflows across the 16 golden configurations
- [ ] Crash-free sessions ≥ 99.5% on the internal track

**Known risk this week:** RTL bugs hide in exactly the screens nobody opens in Arabic — the error
states and the result screen. Audit by *using* the app in Arabic for a full day, not by reading
the diff.

---

## 5. Week 4 — Harden and Ship

**Goal:** an AAB in closed testing with 12 testers and every store form submitted correctly.

| Day | Work | Owner | Done when |
|---|---|---|---|
| 16 | Bug bash: disconnect spam, simultaneous answers, clock edges, 0-answer rounds | All | A written, triaged bug list with zero P0s |
| 16 | Content top-up to 400 if time allows; retire questions outside 15–95% correct | Content | Bank health report is clean |
| 17 | Store assets: icon, feature graphic, 6 screenshots × 2 locales | Designer | Arabic screenshots show Arabic UI, not translated captions on an English build |
| 17 | Listing copy EN + AR, short description, keyword pass | PM | Arabic listing reads natively, not machine-translated |
| 18 | Compliance: privacy policy, Data safety, content rating, target API, AAB signing | Backend | Play Console shows 0 blocking warnings |
| 18 | Account deletion flow (in-app + web link) | Flutter | Deletion completes and the URL is reachable |
| 19 | Upload to **closed testing**, recruit 12 testers, seed instructions | PM | 12 testers accepted and playing |
| 20 | Triage first feedback, fix forward, buffer | All | No P0 open at end of day |

### Google Play checklist

| Item | Detail |
|---|---|
| Package | `gg.gridandglory.app` |
| Signing | Play App Signing; upload key held by the team, never in the repo |
| Format | `.aab` (not APK) |
| Target SDK | Latest required by Play at submission (verify in console — do not hard-code a guess) |
| Min SDK | 24 |
| 16 KB page size | Native libs must comply (required since Nov 2025); verify the Flutter/NDK version produces 16 KB-aligned libs |
| Data safety | Collects device id + gameplay data; **no ads, no third-party ad SDK** — declare exactly that |
| Content rating | IARC questionnaire → expect "Everyone" |
| Privacy policy | Public URL, linked in-app and in the listing, covers both locales |
| Account deletion | In-app path **and** a web URL (both required) |
| Store listing | English **and** Arabic (full localization, not just a translated title) |
| Screenshots | 2–8 phone screenshots per locale, showing real gameplay |
| Feature graphic | 1024 × 500, text-free (it gets cropped in every surface) |
| Icon | 512 × 512, no alpha |
| Testers | **12 testers for 14 consecutive days** for new personal developer accounts — plan the calendar backwards from launch |
| Reviewer access | No login wall; state clearly in the notes that the app is playable as a guest |

**Exit criteria**
- [ ] AAB live in closed testing
- [ ] 12 testers onboarded and active
- [ ] Data safety declaration matches the actual build (an ad SDK added later without updating this is a rejection)
- [ ] Privacy policy and deletion URL resolve publicly

---

## 6. After day 20 — the 14-day window

| Day | Focus |
|---|---|
| 21–27 | Daily crash/feedback triage; ship fixes to the same track. Watch the **locale win-rate** and match-completion rate. |
| 28–31 | Freeze feature work; final content top-up; prepare production rollout notes |
| Day 32 | Apply for production access (if required), then staged rollout **20% → 50% → 100%** over 3 days |
| Day 35+ | Watch p95 latency, crash-free rate, D1 retention, rematch rate |

Do not stage a 100% launch. A 20% rollout turns a catastrophic bug into a bad afternoon.

---

## 7. Cut list — what goes first if the schedule slips

In order. Cut from the bottom.

| # | Cut | Cost of cutting | Why it is cuttable |
|---|---|---|---|
| 1 | Daily Duel | Loses a retention hook | Not needed to prove the 1v1 thesis |
| 2 | Emote pings | Loses a bit of personality | Moderation surface we do not need yet |
| 3 | `blur_reveal` format | Loses one of five formats | The other four carry the game |
| 4 | Ranked ladder (keep unranked + Elo display) | Loses competitive retention | The match itself is the product |
| 5 | `career_path` format | Loses depth | Still four formats |
| 6 | Second language at launch | **Not cuttable.** | Cross-language is the product |

If it gets to #6, ship later, not narrower.

---

## 8. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Content volume insufficient (players see repeats by match 8) | High | High | 400 questions at launch; anti-repetition ledger; weekly top-up |
| R2 | Matchmaking liquidity at launch (nobody to play) | High | High | Soft-launch in 2 regions only; queue-time messaging; widen search aggressively; **do not** add bots to ranked |
| R3 | Arabic quality below native standard | Medium | High | Native linguist signs every question; use the app in Arabic for a full day before ship |
| R4 | Play rejection (data safety / permissions mismatch) | Medium | High | Audit the manifest against the declaration on day 18, not day 20 |
| R5 | MENA latency via a single EU region | Medium | Medium | Deploy a `dxb` node; 8 s cross-region fallback |
| R6 | Scope creep (chat, cosmetics, tournaments) | High | Medium | Cut list is agreed before week 1 and referenced in every scope conversation |
| R7 | Clock drift on low-end Android | Medium | Medium | Server deadlines every event; median-of-5 offset; resync each intro |

---

## 9. Definition of done (per feature)

A feature is done when **all** of these are true:

1. Works in `en` and `ar`, both directions
2. Works at 200% text scale
3. Has an error state with a translated string
4. Has a test (reducer, server, or golden — whichever is cheapest and real)
5. Emits the analytics event that proves it is used
6. Reviewed by someone who did not write it

Anything else is a demo, not a deliverable.

---

## 10. Week-one decisions to lock (before any code)

| Decision | Recommendation | Why now |
|---|---|---|
| Flutter vs React Native | **Flutter** | RTL is a layout-time property, not a per-screen patch |
| Node vs Python backend | **Node + TS** | Timer-driven rooms, single-threaded, shared types with the web tooling |
| One global region vs two | **Two** (`fra`, `dxb`) | Latency for MENA is a product requirement, not an optimization |
| Anonymous-first auth | **Yes** | A signup wall before match one costs > 40% of the funnel |
| Monetization | **None in MVP** | Any paid advantage voids the fairness thesis |
