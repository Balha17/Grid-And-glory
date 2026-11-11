# Frontend Components (Flutter)

**Source:** [`app/lib/
├── main.dart                        # prefs preload → ProviderScope → runApp
├── app.dart                         # MaterialApp: locale → Directionality
├── core/
│   ├── locale/locale_controller.dart # Locale notifier, persisted, device-aware
│   ├── l10n/bidi.dart               # U+2066/U+2069 isolates, Arabic-Indic digits
│   ├── net/ws_client.dart           # framing, clock estimation, heartbeat
│   └── theme/tokens.dart            # colours, spacing, per-locale type scale
├── l10n/
│   ├── app_en.arb                   # 25 keys, source of truth
│   └── app_ar.arb                   # key-for-key parity (CI-checked)
└── features/
    ├── home/home_screen.dart        # language switch + PLAY
    └── match/
        ├── match_flow.dart          # owns the socket: search → match → result
        ├── match_transport.dart     # playerId → you/opponent, round token
        ├── match_view_model.dart    # pure reducer: (state, event) -> state
        ├── match_screen.dart        # 40/60 layout, HUD, formats, overlays
        └── widgets/
            ├── pitch_viewport.dart  # CustomPainter, 6 zones, 2 lanes
            └── answer_button.dart   # AnswerButton + ScoreLine
```
app/lib/
├── main.dart                        # ProviderScope, prefs preload, MaterialApp
├── core/
│   ├── locale/locale_controller.dart # Locale notifier + Directionality shell
│   ├── l10n/bidi.dart               # U+2066/U+2069 isolates, Arabic-Indic digits
│   └── theme/tokens.dart            # colours, spacing, per-locale type scale
├── l10n/
│   ├── app_en.arb                   # 27 keys, source of truth
│   └── app_ar.arb                   # key-for-key parity (CI-checked)
└── features/
    └── match/
        ├── match_view_model.dart    # pure reducer: (state, event) -> state
        ├── match_screen.dart        # 40/60 layout, HUD, quiz panel, formats
        └── widgets/
            ├── pitch_viewport.dart  # CustomPainter, 6 zones, 2 lanes
            └── answer_button.dart   # AnswerButton + ScoreLine
```

Feature-first, not layer-first: a new feature adds a folder, not five edits across five
`lib/screens`, `lib/models`, `lib/widgets` directories.

## 3. Data flow

```
WebSocket frame (JSON)
        │
        ▼
 transport adapter  ── maps playerId keys to 'you'/'opponent', decodes locale strings
        │
        ▼
   reduce(state, event)  ── PURE. no clocks, no network, no async.
        │
        ▼
    MatchUiState  ── immutable value
        │
        ▼
     MatchScreen  ── stateless; renders exactly what it was given
```

```
┌──────────────┐   event    ┌──────────────┐   state    ┌──────────────┐
│  WsTransport │ ─────────▶ │   reducer    │ ─────────▶ │  MatchScreen │
│ (I/O, JSON)  │            │  (pure fn)   │            │  (stateless) │
└──────────────┘            └──────────────┘            └──────────────┘
        ▲                                                        │
        │                  submitAnswer(optionId)                │
        └────────────────────────────────────────────────────────┘
```

**The client never decides anything.** It does not grade an answer, does not run the round
timer, does not extrapolate a score. This is why a modified client is harmless and why a
reconnect is an exact restore rather than a resynchronisation guess.

The one exception is the *visual* countdown: it interpolates toward `windowEndsAt` so the ring
moves smoothly between server events. If it drifts, the next event snaps it back — the server's
verdict is never overridden by local animation.

## 4. The locale pipeline

```
SharedPreferences ('app_locale')
        │
        ▼
 localeControllerProvider ── Notifier<Locale>
        │
        ├─▶ MaterialApp.locale        → ARB selection
        ├─▶ Directionality(textDirection)  → every layout decision in the tree
        └─▶ player_settings push (fire-and-forget)
```

Four rules that make the toggle feel instant rather than like a page reload:

1. **Direction is derived, never stored.** `directionOf(locale)` is the only source. A stored
   direction is how a screen ends up RTL after switching back to English.
2. **The locale is read synchronously at startup.** `SharedPreferences` is preloaded and injected,
   because an async first frame means a visible flash of the wrong language.
3. **No `EdgeInsets.only(left:)`, ever.** Only `EdgeInsetsDirectional`. A single stray `left:`
   is invisible in English and wrong in Arabic — which is why it is a lint rule (§8).
4. **`textDirection` is set explicitly on any `Text` whose content may be the other script.**
   An English club name inside an Arabic card must not inherit the paragraph direction.

## 5. RTL: mapping the spec to code

| Spec rule (`04-ui-ux-spec.md §5`) | Implementation |
|---|---|
| Text alignment mirrors | `Directionality` at the root — free |
| Padding mirrors | `EdgeInsetsDirectional` — enforced by lint |
| Rows reverse | `Row` follows ambient direction — free |
| Directional icons flip | `Icon(..., matchTextDirection: true)` — **not** `Transform.scale` |
| Your lane moves to the right | `_laneXs()` in `pitch_viewport.dart`: `sign = isRtl ? -1 : 1` |
| Pitch does not flip vertically | `_yForZone()` has no `isRtl` parameter at all — structurally impossible to regress |
| Score numerals never reorder | `isoNum()` wraps each run in LRI…PDI |
| Timer ring sweeps clockwise always | `drawArc(..., -pi/2, +2pi * progress)` — no direction input |
| Emoji not re-ordered | Server isolates (U+2066…U+2069); client renders with `TextDirection.ltr` |
| No letter-spacing on Arabic | `AppType.*` returns `letterSpacing: 0` for `ar` |

The strongest of these is the second-to-last: `_yForZone` simply has no way to know the locale, so
"the pitch flipped" is not a bug that can be introduced by a future edit.

## 6. Widget tree — match screen

```
MatchScreen
└── SafeArea
    └── LayoutBuilder                          ← 40/60 computed from available height
        └── Column
            ├── SizedBox(height: 40%)
            │   └── Stack
            │       ├── PitchViewport          ← CustomPainter, RepaintBoundary
            │       │   └── TweenAnimationBuilder (you) → TweenAnimationBuilder (opponent)
            │       └── PositionedDirectional  ← HUD overlays, not a sibling row
            │           └── _MatchHud
            │               ├── possession dot
            │               ├── ScoreLine
            │               ├── _TimerChip → _RingPainter
            │               └── half label
            └── SizedBox(height: 60%)
                └── _QuizPanel
                    ├── Row: ROUND n · "Opponent answered"
                    ├── Expanded → ConstrainedBox(min 96) → _QuestionCard
                    │   └── SingleChildScrollView
                    │       ├── prompt Text (maxLines 3)
                    │       └── _FormatBody  ← one widget per format
                    └── AnswerButton × 4
```

Why `Expanded` only on the question card: the answers must never move under the thumb mid-round.
The overflow ladder from the spec is encoded by giving exactly one element the ability to shrink.

## 7. Pitch widget contract

```dart
PitchViewport(
  yourZone: 0..5,        // clamped by the caller; the painter assumes valid input
  opponentZone: 0..5,
  youHaveBall: bool,     // draws the possession glow and places the ball
  locale: Locale,        // used only for lane assignment
  goalFlash: bool,       // 900 ms celebration tint
)
```

- Two independent `TweenAnimationBuilder`s: the avatars move at different speeds and must not
  share a timeline.
- `RepaintBoundary` around the `CustomPaint` so a zone animation does not repaint the quiz panel.
- No zone numbers during play. They are useful in the tutorial and in the result card, and noise
  at 9 seconds.

## 8. Answer button contract

```dart
AnswerButton(
  label: String,
  state: idle | selected | correct | wrong | disabled,
  locale: Locale,
  onPressed: VoidCallback?,
)
```

Invariants:
- `minHeight: 56`, always — text scaling must grow the row, never clip it.
- State is carried by **glyph + border + colour**, never colour alone.
- **No optimistic colouring.** Pressing an answer shows `selected` (neutral amber), not `correct`.
  Showing green before the server has ruled is a lie that costs trust the first time it is wrong.
- `onPressed` is `null` when disabled, so the semantics tree reports the button as disabled too.

## 9. Blur & Reveal timing

The blur is a speed mechanic, so its curve is tied to the round deadline rather than to a local
animation started on tap. `_BlurReveal` animates `ImageFilter.blur` sigma from
`initialBlurSigma` to `finalBlurSigma` over `revealMs`, both supplied by the server per question.
Under `MediaQuery.disableAnimations` it renders the final state directly rather than a static
blur, because a permanently unreadable image is worse than no animation.

## 10. Performance budget

| Target | Approach |
|---|---|
| 60 fps pitch on a 4 GB Android | `CustomPainter` + `RepaintBoundary`; no per-frame widget rebuild |
| < 16 ms frame on reveal | Pre-decoded image, blur sigma animation is GPU-side |
| Cold start < 1.8 s | No engine init; prefs preloaded; fonts subset |
| Memory < 180 MB | Blur assets capped at 1080 px wide, WebP |
| Jank-free list | No `ListView` in the match path |

## 11. Testing

| Layer | How |
|---|---|
| Reducer | Plain Dart tests: feed event fixtures, assert state. No widget pump needed. |
| RTL | Golden tests rendered at `TextDirection.rtl` **and** 200% text scale, both locales |
| Overflow | Golden tests at 320×568 (small phone) and 430×932 (large) |
| Bidi | Unit tests asserting `isoNum('2 – 1')` keeps order under an RTL paragraph |
| ARB parity | CI check that `app_ar.arb` has exactly the keys of `app_en.arb` (27 each, verified) |
| Pitch | Painter unit test: zone → y monotonically decreasing; lane x flips with `isRtl` |

The reducer being pure is what makes most of this cheap. Widget tests are reserved for layout and
direction, which is exactly where widget tests earn their cost.

## 12. Deliberately not in the client

- No question bank or answer key (never shipped)
- No matchmaking logic
- No score calculation
- No timer authority
- No offline match engine

If any of these appear in the client later, the anti-cheat model in
[`docs/03-realtime-matchmaking.md §9`](03-realtime-matchmaking.md) is void.

---

## 13. Boot sequence

```
main()
  └─ SharedPreferences.getInstance()        ← awaited BEFORE the first frame
       └─ ProviderScope(override: prefs)
            └─ GridAndGloryApp              ← watches locale
                 └─ MaterialApp(locale: …)  ← WidgetsApp derives Directionality
                      └─ HomeScreen
                           └─ MatchFlowScreen   (owns the GameSocket)
                                ├─ searching   ← Connected, queued
                                ├─ found       ← opponent's language is shown
                                └─ playing     ← MatchScreen + MatchTransport
```

Three lifetimes, deliberately nested:

| Object | Lifetime | Why |
|---|---|---|
| `GameSocket` | one visit to the arena | A socket surviving the screen is a leak; a socket per phase is a reconnect bug |
| `MatchTransport` | one match | Holds the round token; a stale token must not survive a rematch |
| `reduce` | pure function | No lifetime, no disposal, trivially testable |

`MatchFlowScreen` owns the first two because the three phases (searching, playing,
finished) share one connection. Pushing a route per phase is what creates matches that
reconnect themselves.

## 14. The structural gate

There is no Flutter SDK in this repository's environment, so `dart analyze` cannot run.

```bash
npm run check:app        # node app/tools/check.mjs
```

It checks the things a compiler would catch first, plus the project's RTL rule:

1. balanced `()`, `{}`, `[]`
2. every relative import resolves (generated `app_localizations.dart` excepted)
3. every `l10n.key` exists in **both** ARB files
4. ARB placeholders match across locales and actually appear in the strings
5. no `EdgeInsets.only(left:)`, `Positioned(left:)`, `Alignment.centerLeft`, …

It is honest about being an approximation, and it has been negative-tested — a single
`EdgeInsets.only(left: 24)` fails the gate. But a green run means "structurally sane",
not "compiles". Run `flutter analyze` on the first machine that has an SDK.
