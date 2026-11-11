# Release Runbook — from repo to Play Store

This is the "final phase". Every step is a command you can run; nothing here is aspirational.

> **Read first:** an APK cannot be built on every machine. Flutter publishes **no ARM64
> Linux SDK** (0 of 749 releases), so an aarch64 host — including the one this repo was
> written on — cannot run the toolchain at all. Use an x86-64 machine or CI.

---

## 0. Prerequisites

| Tool | Version | Check |
|---|---|---|
| Flutter | stable ≥ 3.24 | `flutter --version` |
| JDK | 17 | `java -version` |
| Android SDK | API 35+, build-tools 35 | `flutter doctor` shows Android toolchain ✓ |

`flutter doctor` must show a green Android toolchain before anything else is worth doing.

## 1. Generate the Android project and signing key

```bash
bash app/tools/prepare-android.sh   # creates android/, applies the four fixes
bash app/tools/keystore.sh          # creates upload-keystore.jks + key.properties
```

`keystore.sh` prints the SHA-1 and SHA-256 fingerprints — copy them into the Play Console
(and Firebase, if used). **Back up the `.jks` and the passwords.** Losing them means you can
never update this listing again; a leaked one means someone else can.

`key.properties` and `*.jks` are already in `.gitignore`. For CI, store them as repository
secrets and write them back in a build step.

## 2. Build

```bash
cd app
flutter pub get
flutter gen-l10n
flutter analyze                # the first REAL compile of this Dart

# Fastest installable artifact for testers:
flutter build apk --release --dart-define=WS_URL=wss://ws.your-host/ws

# What Play actually wants:
flutter build appbundle --release --dart-define=WS_URL=wss://ws.your-host/ws
```

| Output | Path | Use |
|---|---|---|
| APK | `build/app/outputs/flutter-apk/app-release.apk` | sideload / testers |
| AAB | `build/app/outputs/bundle/release/app-release.aab` | Play upload |

**The `WS_URL` matters.** It is baked in at compile time. A build pointed at
`ws://192.168.1.20:8080` will work on your sofa and nowhere else; a release build must use
`wss://`. The debug manifest permits cleartext, the release manifest does not.

## 3. Play Console

| Step | Detail |
|---|---|
| Create app | Name `Grid & Glory`, default language English, **add Arabic as a second listing language** |
| Store listing | Short description (80 chars), full description, icon 512×512, feature graphic 1024×500 |
| Screenshots | 2–8 per language. The Arabic set must show the Arabic UI, not translated captions on an English build |
| Data safety | Declare: device id, gameplay data. **No ads.** Match this exactly to the build |
| Content rating | IARC questionnaire → expect Everyone |
| Privacy policy | Public URL, linked in-app and in the listing |
| Account deletion | In-app path **and** a web URL — both required |
| Target API | Whatever Play currently requires (check the console; do not guess) |
| Testing track | Internal → Closed |

## 4. The 14-day clock

New **personal** developer accounts must run closed testing with **12 testers for 14
consecutive days** before production access. Work backwards from your launch date; this is
calendar time you cannot compress.

```bash
# recruit, then share the closed-testing opt-in URL
```

Use the window to watch — not to add features:

- crash-free sessions ≥ 99.5%
- match completion ≥ 92%
- **locale win-rate delta < 5 points** (the whole product thesis in one number)
- p95 answer→ack < 180 ms

## 5. Rollout

```
20% → 50% → 100%, one day apart
```

Halt on: crash-free < 98.5%, match completion < 80%, or a locale delta > 8 points. A 20%
rollout turns a catastrophic bug into a bad afternoon.

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| App installs, cannot connect | Missing `INTERNET` in the release manifest | Re-run `prepare-android.sh` |
| `ws://` fails on device only | Cleartext blocked (API 28+) | Use `wss://` for release |
| Works on emulator, not on phone | `WS_URL` points at `10.0.2.2` | Rebuild with the LAN IP or a real host |
| Play rejects the upload | Signed with the debug key | Run `keystore.sh`, rebuild |
| Arabic text clipped | Latin line-height on Arabic | Line height is per-locale in `AppTokens`; check `AppType` |
| `flutter analyze` fails on first run | The Dart was never compiled before | Expected. Fix the type errors; they are real |

---

## Where the APK comes from if you have no x86-64 machine

`.github/workflows/android.yml` builds both artifacts on an x86-64 runner:

```
GitHub → Actions → android-apk → Run workflow → ws_url = wss://your-host/ws
```

Artifacts appear under the run summary, retained 14 days. That is the supported path from an
ARM host, and it is the one this repo was designed around.
