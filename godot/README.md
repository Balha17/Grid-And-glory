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
