# Affinity iOS app

SwiftUI, iOS 17+, Xcode 16.

## Open and run

1. Open `ios/Orbit.xcodeproj`.
2. Xcode needs the **iOS platform** installed: Xcode → Settings → Components → iOS → Get. This is a one-time download of about 8 GB, needed for both the Simulator and real iPhones.
3. Target **Orbit** → Signing & Capabilities → pick your **Team** (a free Apple ID works). If the bundle id `com.cnh.orbit.app` is taken, change it to something unique, like `com.<yourname>.orbit`.
4. Plug in your iPhone, turn on Developer Mode (Settings → Privacy & Security → Developer Mode), pick it as the run destination, and press ⌘R.

## Folders: just add files

The `Orbit/` folder is **synced**. Any `.swift` or `.json` file you drop into it is part of the app automatically, so nobody has to edit the project file.

| Folder | Owner |
|---|---|
| `App/`, `Core/`, `Onboarding/`, `Radar/` | Jenish |
| `Talks/`, `Calendar/`, `People/`, `Matches/`, `Components/` | Teammate C. See [`TEAMMATE_C.md`](TEAMMATE_C.md) |

## Data

- `Core/Models.swift` contains every type in the API contract (`PLAN.md`). `Core/APIClient.swift` has one async method per endpoint, e.g. `try await APIClient.shared.recommendedTalks(pid:)`.
- **Stub mode is on by default.** Every call returns the JSON in `Core/Stubs/`, so screens work before the backend exists.
- Switch to the live backend at runtime with the **gear icon** → Developer → set the base URL, then turn off "Use stub data".
- The signed-in user is `appState.profile` (`@Environment(AppState.self)`). `appState.findOnRadar(pid:)` jumps to the Radar tab.
- "Use the demo profile" on the onboarding screen skips straight to the tabs.
