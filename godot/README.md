# Grid & Glory — Godot 4 client

This is the new native Godot 4 client. The Node.js/TypeScript match server and bilingual question bank remain authoritative and are intentionally shared; only the game client/rendering layer is being migrated.

## What is in this first migration slice

- A dedicated HD-styled main menu with a custom shield/football icon and illustrated stadium backdrop.
- The 3D stadium is hidden on the home screen and only shown during an active match; it is hidden again at full time.
- A high-contrast, responsive question panel with larger answer cards and an in-game sound mute toggle persisted between launches.
- Seven image-dependent questions with missing image files were rewritten as complete bilingual text questions; CI now validates every prompt, option, answer, explanation, and referenced asset.
- Pitch markings, penalty areas, goals and net frames, stadium seating, lights and shadows.
- Two full 11-player formations with team colours and zone-driven movement.
- A Godot `WebSocketPeer` client using the existing version-1 JSON protocol and production WSS endpoint.
- Online matchmaking, bot-match request, question/options, answer token submission, round results, score and full-time UI.

## Open locally

Use Godot **4.4.1 stable** or newer 4.x:

1. Import `godot/project.godot`.
2. Run the main scene.
3. Ensure internet access for online or bot matches.

The server remains at `wss://grid-and-glory.onrender.com/ws`. AI matches still require the server; this is not offline mode.

## Android

The `godot-android.yml` workflow installs Godot export templates and the Android toolchain, then creates a debug APK artifact. The existing Flutter client is retained as a fallback during migration; it is not the new 3D client.

## Current limitations

This is the first 3D client foundation, not a full FIFA-style simulation. The 3D team movement is currently driven by the match's zone/possession state; player locomotion, ball physics, tackles, goalkeeper AI, and complete animation sets are follow-up work. The server remains the sole authority for questions, answer timing and scoring.

## Audit and current engineering notes

The Android client currently boots from `scenes/main.tscn` (one `Node3D`) and builds its stadium, menu, match HUD, WebSocket client, settings and audio at runtime in `scripts/game.gd`. There are no autoload singletons yet. This is workable for a prototype, but the 1,200+ line script is a maintainability risk: the next architecture step should split it into `MatchClient.gd`, `MatchHUD.gd`, `MainMenu.gd`, `Stadium.gd` and a small settings service, each with its own scene/script boundary.

The bank currently contains 164 bilingual questions: 139 multiple choice, 8 career paths, 9 emoji stories and 8 stat comparisons. It currently contains **zero media entries and zero `image_path` fields**, so the image viewer is implemented but there are no actual question pictures to display yet. The server remains authoritative for matchmaking, question delivery, timing and scoring; the AI opponent still requires the online server.

## Question images

Add an optional top-level `image_path` to a question record. Use a bundled path for an image shipped inside the APK, or HTTPS for an image hosted online:

```json
{
  "id": "q_mc_example",
  "image_path": "res://assets/questions/example-stadium.webp"
}
```

- For a bundled image, place the file under `godot/assets/questions/` and use its exact `res://assets/questions/...` path. CI verifies the file exists.
- For a hosted image, use a stable HTTPS URL. Android Internet permission is already enabled. The client displays a loading/failure placeholder and supports WebP, PNG and JPEG.
- Keep image files licensed for redistribution, compressed (prefer WebP) and reasonably small. Do not add a picture question without a real image.
- `image_path` is passed by the server as `imagePath`; the client accepts local `res://`, downloaded `user://` or HTTP(S) sources.

## Apply and validate

1. Edit the question in `db/seed/bank.en-ar.v1.json` and add `image_path` only when the actual image exists.
2. Keep the question bilingual and retain the stable `answerOptionId`; never send the answer key in the question view.
3. Commit to `main`. GitHub Actions runs the server tests and the Godot headless import/script check.
4. On a successful `godot-android` run, download the `grid-and-glory-godot4-apk` artifact from that run's Artifacts section and extract the APK.

## Known limitations after this pass

- The 3D players are still procedural capsule/sphere figures with simple limb motion, not licensed character models or a full football simulation.
- Match movement is zone-driven; it is not physics-based gameplay.
- Audio is currently downloaded at runtime from external URLs. For a production release, replace this with bundled, licensed sound files and attribution records.
- No offline question/bot mode exists; even AI matches use the online match server.
- The current scene architecture is still monolithic. A full scene/component split and device-level RTL/responsive QA remain required before calling the game production-ready.