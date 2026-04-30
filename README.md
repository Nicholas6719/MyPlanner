# MyPlanner

A personal weekly planner + task tracker for iOS and macOS, built as a single
SwiftUI multiplatform app. Type things like *"Working Monday 7am to 3:30pm"*
or *"Math homework due Friday"* into the bar at the bottom — the app figures
out whether it's an event or a task and files it correctly.

## Run it

1. Open `MyPlanner.xcodeproj` in Xcode 16+.
2. Open the project's **Signing & Capabilities** tab and pick your **Personal
   Team** (the free Apple Developer account associated with your Apple ID).
3. Pick a target — the iPhone simulator, an attached iPhone, or "My Mac" —
   and hit **Run** (⌘R).

Min OS: iOS 17 / macOS 14. Built and tested on Xcode 26.

## Features

- **Three top-level views**: Week (7-day grid), Day (single day with bigger
  cards + tasks-due-today strip), Tasks (filter chips + list).
- **Composer bar** at the bottom of every screen with a live preview of how
  your text will be parsed. Type "Event" / "Task" toggle in the preview lets
  you override classification.
- **Natural language parsing** via `NSDataDetector` plus custom regex for
  recurrence keywords ("every", weekday names) and time-of-day fallbacks.
- **Weekly recurring events** with multi-weekday selection.
- **Local notifications** with quick-add reminder offsets (1 day / 1 hour /
  30 min / custom).
- **JSON Export / Import** for manual backup and sync between devices.
- **Categories** with custom names and colors.
- **Dark theme** designed from the spec's color tokens.

## Sync workflow (current)

Because this builds against the **free Apple Developer account**, CloudKit
sync is disabled. To move data between devices today:

1. **Settings → Backup → Export JSON** on the source device.
2. Share the resulting file via **AirDrop**, **Save to iCloud Drive**, or
   email.
3. Open the file on the target device, **Settings → Backup → Import JSON**,
   and confirm. (Importing replaces all current data.)

## Enabling CloudKit later

When you upgrade to a paid Apple Developer account, real iCloud sync is a
two-line change. See the **`TODO: CloudKit`** block in
[`MyPlannerApp.swift`](MyPlanner/MyPlannerApp.swift):

1. In Xcode: target → **Signing & Capabilities** → add **iCloud** capability,
   tick **CloudKit**, add a container (e.g. `iCloud.Coppola.MyPlanner`).
2. Add **Background Modes** → **Remote notifications**.
3. Replace the `ModelConfiguration` constructor with the CloudKit version
   shown in the comment block.

The data model was designed CloudKit-friendly from day one (defaults on
every property, no required relationships, enums stored as strings), so no
schema migration is needed.

## Project layout

```
MyPlanner/
├── MyPlannerApp.swift          App entry, ModelContainer + CloudKit TODO
├── RootShell.swift             Topbar + tabs + composer
├── Theme/                      Color tokens, typography, components
├── Models/                     SwiftData @Model classes
├── Services/                   NLParser, Recurrence, Notifications, Backup
└── Features/                   Week, Day, Tasks, Composer, Editors, Settings
```

`MyPlannerTests/MyPlannerTests.swift` covers the natural-language parser and
recurrence expansion.

## Testing

```sh
xcodebuild -project MyPlanner.xcodeproj \
           -scheme MyPlanner \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           -only-testing:MyPlannerTests test
```
