# Grid & Glory — Unity client (migration in progress)

The new native 3D client is being migrated to **Unity 2022.3 LTS**. The existing Node.js/TypeScript backend and bilingual question bank remain authoritative and unchanged. The Godot client is retained temporarily as a fallback while the Unity client is validated.

## Unity project

Open the `unity/` folder in Unity 2022.3 LTS. The bootstrap creates the menu, 3D pitch/stadium, player formations, question UI and WebSocket client at runtime.

- Portrait Android layout; 3D stadium is rendered behind a bottom question dock.
- PLAY VS AI requests an AI match directly; PLAY ONLINE enters matchmaking (AI fallback after 15 seconds).
- Uses the existing version-1 WebSocket protocol at `wss://grid-and-glory.onrender.com/ws`.
- Correct answers turn green; selected wrong answers turn red.
- Career-path and emoji clues are rendered from the server's localized `formatData`.

## Android CI

The workflow `.github/workflows/unity-android.yml` builds a debug APK with GameCI. It requires a Unity Personal/Pro license stored as the repository Actions secret `UNITY_LICENSE`. Without that secret, GitHub Actions cannot activate the Unity Editor and cannot produce an APK. Add the license XML exported from Unity Hub to that secret, then run the workflow.

## Current scope and honest limitations

This is the first Unity migration slice, not a finished FIFA-style game. It includes a procedural 3D pitch, simple stadium seating, primitive player models, menu/matchmaking, question rendering and server-authoritative match flow. It does not yet include realistic player meshes, motion-capture animations, ball physics, goalkeeper AI, crowd/audio assets or offline AI. Those need dedicated assets and follow-up development.

The old Flutter and Godot sources remain in the repository during migration; the Unity project is the new target, not yet a verified release APK.
