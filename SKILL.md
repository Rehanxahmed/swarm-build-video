---
name: swarm-build-video
description: Make a "swarm build" video of an iOS app screen. Figma-style multiplayer cursors build the real SwiftUI screen in about 12 seconds (red guides, grey boxes that turn into cards, typed text, alt-drag copies, one joke typo fixed at the end). It's recorded on the iOS Simulator and rendered as an MP4 in a phone mockup. Use when someone asks for a swarm video, a swarm build, or "cursors building my screen" for a SwiftUI app. Needs a Mac with Xcode, the iOS Simulator and ffmpeg.
---

# Swarm build video

You turn one screen of the person's SwiftUI app into a 12-second clip where
four multiplayer cursors build it live, the way a design file comes together:

- Red margin guides slide in from the edges.
- A cursor crosshair-drags a grey box with a size pill, and it becomes the real card.
- Headlines are typed small behind a caret, then stepped up to size.
- Repeated items are built once, then alt-dragged into place with a red measure and retyped.
- Lines are penned, icons dropped in, images swapped into their grey boxes.
- Near the end, one cursor double-clicks a word typed wrong ("Good morming") and fixes it.
- The cursors leave and the finished screen holds for a beat.

One cursor carries the person's first name; the other three are unlabelled.
The real screen is what gets built. The engine animates the app's own views,
so the final frame *is* the app.

Outputs: `<name>.mp4` (phone mockup, 1440×1800, 60 fps), `<name>-screen.mp4`
(bare screen) and `<name>-sheet.png` (contact sheet), in `~/Movies/Swarm/`.

**Keep it quick.** Do one build pass, check the stills and the contact sheet,
then deliver. Offer a polish pass rather than looping on it unasked.

## Ground rules

- **Never touch the person's real project.** Everything happens in a copy.
- Only SwiftUI screens. If the screen is UIKit, say so and stop.
- Show the screen at its best: real layout, believable full content (seed
  demo data in the copy), no login, onboarding or empty states.
- iOS 17+ for the engine. In the copy you may raise the deployment target.

## Steps

### 1. Preflight

```bash
xcodebuild -version && xcrun simctl help >/dev/null && which ffmpeg python3
```

If ffmpeg is missing, ask before running `brew install ffmpeg`. Note the
skill's own folder (where this file is) as `SKILL_DIR`.

### 2. Pick the screen and the name

- **Screen:** if the person didn't name one, pick the app's main or home screen and say which.
- **Name:** use the person's first name for the labelled cursor if you know it.
  Otherwise use the first word of `id -F`. The output name is `<App>-<Screen>`.

### 3. Copy the project

```bash
WORK="${TMPDIR:-/tmp}/swarm-video/<AppName>"
rm -rf "$WORK" && mkdir -p "$WORK"
rsync -a --exclude .git --exclude build --exclude DerivedData --exclude '*.xcresult' <project-root>/ "$WORK/"
```

The project root is the folder holding the `.xcodeproj`, `.xcworkspace`,
`project.yml` or `Package.swift`. If the project refers to files outside that
folder (`../Shared`, local packages), copy the common parent instead.

### 4. Add the engine

`SKILL_DIR/engine/SwarmKit.swift` is the whole engine: one self-contained
file, no dependencies. Get it into the app target in the copy:

| Project kind | How |
|---|---|
| Xcode 16+ folders (`PBXFileSystemSynchronizedRootGroup` in `project.pbxproj`) | copy the file into the app's source folder |
| XcodeGen (`project.yml`) | copy it into a source folder, then run `xcodegen generate` |
| Swift Package / Tuist | copy it into the app target's sources |
| Classic groups (anything else) | append its contents to the end of the target screen's `.swift` file, and move its `import` lines to the top (no duplicates) |

### 5. Make the app open straight on the screen

In the copy, change the `App`'s root so it shows the target screen directly,
with demo data and any environment objects it needs. Skip launch gates,
splash screens, auth and paywalls. If the screen lives in a `TabView` or
`NavigationStack`, keep that chrome so it looks real.

### 6. Wire the build

Read `SKILL_DIR/reference/choreography.md` first. It has the moves, the
timing, the patterns (cards, repeated rows, images, the joke fix) and the
gotchas.

1. On the screen's root view: `@State private var build = <Screen>Build.make()` and `.swarmStage(build)`.
2. Tag every piece visible on the first screen with `.swarm("id")`.
   - Anything visible that isn't tagged shows from the first frame, so tag it or let it be the page itself.
   - Don't tag what's below the fold.
3. Write `<Screen>Build.make()`: the steps (id, cursor, start, length, move), `SwarmBuild.crew(named: "<FirstName>")`, and `length` ≈ 10.5–11.2 s.

Without `-swarm` the screen opens finished, so normal launches are unaffected.

### 7. Build for the simulator

```bash
cd "$WORK"
xcodebuild -list                      # find the scheme
xcodebuild -project <App>.xcodeproj -scheme <Scheme> -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$WORK/build" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
APP=$(find "$WORK/build/Build/Products" -maxdepth 2 -name '*.app' -path '*iphonesimulator*' | head -1)
```

Use `-workspace <App>.xcworkspace` instead if there is one (CocoaPods).

### 8. Check stills before recording

```bash
python3 "$SKILL_DIR/scripts/still.py" --app "$APP" --at 0.3 2 4 6 8.5 99 --out "$WORK/stills.png"
```

Each moment is a fresh launch frozen at that time on a dedicated simulator
("Swarm Recorder", created on first use; the first run takes about a
minute). Look at the image:

- **0.3 s** must be the empty page, plus system chrome like the status bar and tab bar. Anything else showing is untagged or has a typo'd id.
- **Mid-build** frames should show marks: grey boxes, selection, caret, red measures.
- **99** must be the finished screen exactly as the app normally looks.

Fix what's off, rebuild, re-check.

### 9. Record and render

```bash
python3 "$SKILL_DIR/scripts/record.py" --app "$APP" --seconds <length + 2.5> --out "$WORK/takes" --name take
python3 "$SKILL_DIR/scripts/render.py" "$WORK/takes/take.mov" --out ~/Movies/Swarm/<App>-<Screen>
```

- **record.py** launches the screen as an empty page, starts recording, then cues the build. No launch animation ends up in the take.
- **render.py** finds the first and last movement on its own, cuts from just before the first cursor to a held final frame (12 s by default, `--duration` to change), and writes the mockup, the bare screen and a contact sheet.
- Add `--dark` to record.py for dark-mode screens, and `--args "..."` for any demo-mode flags the copy needs.

### 10. Look, then deliver

Read `<name>-sheet.png`. Check:

- The page starts empty.
- Pieces arrive one at a time, with two or three cursors busy at once.
- Nothing pops in at the very end.
- The typo gets fixed.
- It ends on the finished screen.

If something is clearly broken, fix it once and re-record. Then tell the person:

- the paths to the two videos
- the order things get built and the joke fix
- that their real project was not modified, and that the working copy is at `$WORK` if they want tweaks

## Troubleshooting

| Symptom | Fix |
|---|---|
| render.py says nothing moves | `.swarmStage(build)` missing, the app doesn't open on the screen, or the screen isn't built with `-swarm`. Run still.py at 2 s to see. |
| Something visible from the first frame | It's untagged, or its id isn't in the steps (unknown ids count as finished). |
| A cursor jumps instead of gliding | Two of its steps overlap or sit too close. Leave ≥ 0.2 s between one cursor's steps. |
| Cursor flies to the top-left corner | That step's view never got a frame (not on screen). For guides and parks, use `build.pin` / `build.park`. |
| Marks clipped inside a `List` | In the copy, swap the `List` for `ScrollView { VStack }` with the same row views. |
| Large navigation title can't be typed | In the copy, hide the system title and put a `Text` header in the content instead. |
| A setup banner shows in the take | A brand-new simulator. Record again; the banners only come once. |
