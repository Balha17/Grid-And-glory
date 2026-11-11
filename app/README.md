# Flutter client

The app shell for Grid & Glory: locale plumbing, the 40/60 match screen, the pitch
painter, and the WebSocket transport.

> **No Flutter SDK is installed in this repository's environment**, so this code has
> never been compiled. It is written to be analysed and run, and `app/tools/check.mjs`
> enforces the structural rules that a compiler would catch first — but treat the first
> `flutter analyze` as a real gate, not a formality.

---

## Run it

```bash
cd app
flutter pub get
flutter gen-l10n            # generates lib/l10n/app_localizations.dart (not committed)

# Android emulator reaches the host on 10.0.2.2
flutter run --dart-define=WS_URL=ws://10.0.2.2:8080/ws
```

Start the server first:

```bash
cd .. && npm run serve
```

Then two clients — one running in English, one switched to العربية — will be matched
against each other, because **matchmaking never filters by language**.

## Build an APK

An APK requires Flutter + the Android SDK + a JDK on an **x86-64** host. Flutter ships no
ARM64 Linux SDK (0 of 749 releases), so an aarch64 machine cannot build this — or any
Flutter app — at all. Use CI or an x86-64 laptop.

### Via CI (recommended)

```
GitHub → Actions → android-apk → Run workflow → ws_url = wss://your-host/ws
```

Artifacts: `app-release.apk` (installable, debug-signed) and `app-debug.apk`.
The workflow runs `flutter analyze` first — that is the **first real compile** of this
Dart, so expect it to surface type errors the structural checker cannot see.

### Local

```bash
flutter doctor                       # must show Android toolchain ✓
bash tools/prepare-android.sh        # generates android/ and applies the four fixes
bash tools/keystore.sh               # release signing key (once; back it up)
flutter pub get && flutter gen-l10n
flutter analyze                      # the real gate

# Point the client at a reachable server. For a phone on the same Wi-Fi use the LAN IP,
# NOT localhost: localhost on a phone is the phone.
flutter build apk --release --dart-define=WS_URL=wss://your-host/ws

# Or a quick installable build for testing against a laptop server:
flutter build apk --debug --dart-define=WS_URL=ws://192.168.1.20:8080/ws
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

For the Play Store, build an app bundle instead:

```bash
flutter build appbundle --release --dart-define=WS_URL=wss://your-host/ws
```

Full sequence, including the Play Console forms and the 12-tester / 14-day rule:
[`RELEASE.md`](../RELEASE.md).

### What `prepare-android.sh` fixes

`flutter create` produces an Android project that is wrong for this game in four ways:

| Fix | Why |
|---|---|
| `INTERNET` in the **release** manifest | `flutter create` only adds it to debug/profile. A release APK installs and then cannot open a socket. |
| Localised `app_name` (`values/`, `values-ar/`) | Without it, an Arabic phone shows the English name on the launcher. |
| `applicationId = gg.gridandglory.app` | The default is `gg.gridandglory.grid_and_glory`, derived from the Dart package name. |
| Cleartext HTTP in **debug only** | Android blocks `ws://` since API 28. Enabling it in release would permit a downgrade attack. |

The script is idempotent and has been tested against a mock `flutter create` scaffold
(the assertions cover all four patches plus re-run safety).

## Structure

```
lib/
├── main.dart                    prefs preload → ProviderScope → runApp
├── app.dart                     MaterialApp: locale → Directionality
├── core/
│   ├── locale/                  Locale notifier, persisted, device-aware on first run
│   ├── l10n/bidi.dart           U+2066/U+2069 isolates, Arabic-Indic digits
│   ├── net/ws_client.dart       framing, clock estimation, heartbeat
│   └── theme/tokens.dart        colours, spacing, per-locale type scale
├── l10n/                        app_en.arb, app_ar.arb (key-for-key parity)
└── features/
    ├── home/                    language switch + PLAY
    └── match/
        ├── match_flow.dart      owns the socket: searching → match → result
        ├── match_transport.dart playerId → you/opponent, holds the round token
        ├── match_view_model.dart pure reducer (state, event) → state
        ├── match_screen.dart    40/60 layout, HUD, formats, overlays
        └── widgets/             pitch painter, answer button
```

## The three layers, and why

| Layer | Owns | Rule |
|---|---|---|
| `GameSocket` | framing, clock, reconnect | Knows nothing about football |
| `MatchTransport` | id mapping, round token | Knows nothing about widgets |
| `reduce` | state transitions | Pure. No clock, no I/O, no `BuildContext` |

The client is a renderer, not a referee. It never grades an answer, never decides the
score, and never extrapolates the clock — those are server facts. That is what makes a
patched client harmless.

## RTL contract

`MaterialApp.locale` is the single source of direction: `WidgetsApp` derives
`Directionality`, and every `Row`, `EdgeInsetsDirectional` and `PositionedDirectional`
below it flips automatically. There is deliberately no second `Directionality` wrapper.

What does **not** mirror, and is enforced in code:

- the pitch's vertical axis — `_yForZone()` has no locale parameter at all
- the timer ring — always clockwise
- numerals in a scoreline — wrapped by `isoNum()`
- emoji — isolated server-side, rendered `TextDirection.ltr`
- letter-spacing on Arabic — `AppType` returns `0` for `ar`

## The structural gate

```bash
node ../app/tools/check.mjs     # or: npm run check:app from the repo root
```

Checks, in the absence of `dart analyze`:

1. balanced `()`, `{}`, `[]` — the file parses
2. every relative import resolves
3. every `l10n.x` exists in **both** ARB files
4. ARB placeholders match across locales and appear in the strings
5. no `EdgeInsets.only(left:)`, `Positioned(left:)`, `Alignment.centerLeft`, …

It is an approximation and says so in its own output. It has been negative-tested: a
single `EdgeInsets.only(left: 24)` fails the build.

## Not done yet

- Fonts: Arabic needs a real face (`IBMPlexSansArabic`). The `pubspec.yaml` block is
  commented out until the files exist — synthetic bold smears Arabic letter joins.
- Widget and golden tests (the reducer is ready for them; `reduce` is pure).
- iOS project configuration.
- The `blur_reveal` asset host: `Image.network` points at whatever `assetUrl` the
  server sends, which is a placeholder CDN until assets are licensed.
