---
name: swarm-build-video
description: Make a "swarm" video of an iOS app screen with Figma-style multiplayer cursors, recorded on the iOS Simulator and rendered as an MP4 in a phone mockup. Two films. Build (12 s), where the cursors build the real SwiftUI screen from nothing (red guides, grey boxes that turn into cards, typed text, alt-drag copies, one joke typo fixed). Before → After (about 19 s), where the screen opens on the old design and the cursors make each product design decision on it (comment pins explaining why, strike-and-remove, restyles with an inspector pill, moves), ending on the real new design and a side-by-side end card. Use when someone asks for a swarm video, a swarm build, "cursors building my screen", or a before/after, redesign or design-decision video of a SwiftUI screen. Needs a Mac with Xcode, the iOS Simulator and ffmpeg.
---

# Swarm build video

One skill, two films. Both use the same engine, scripts and phone mockup.

| Film | What it shows | Length |
|---|---|---|
| **Build** (default) | four cursors build the screen from an empty page | 12 s |
| **Before → After** | the old screen; the cursors make each design decision on it; the new screen; an end card with both | ~19 s |

## The Build film

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

## The Before → After film

For showing product design decisions. The screen opens on the **old** design
with a "Before" label under the phone. Then, one decision at a time, a cursor
drops a comment pin with a note saying what's wrong ("32 pt buttons miss the
44 pt minimum tap target"), and another cursor makes the change: strikes out
and removes the old piece, draws in the new one, restyles with an inspector
pill (`32 pt → 44 pt`), or drags a piece to its new place. It ends on the
real **new** screen with an "After" label, then crossfades to an end card:
the two screens side by side with the decisions listed under them.

Both ends are real: the first frame is the old screen as it really looked,
the last frame is the new one.

## Outputs

In `~/Movies/Swarm/`:

- `<name>.mp4`: the phone mockup, 1440×1800, 60 fps
- `<name>-screen.mp4`: the bare screen
- `<name>-sheet.png`: a contact sheet
- Before → After also writes `<name>-compare.png`, the end card as a still for case studies and slides
- `--vertical` adds `<name>-9x16.mp4` (1080×1920) for stories and reels, for either film

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

### 2. Pick the film

- They mention before/after, a redesign, "what changed", design decisions or a comparison: **Before → After**.
- They ask for a swarm video or build with nothing else: **Build**.
- Unclear: ask which, in one question, with the two lengths.

For Before → After, also settle (read `reference/decisions.md` first):

- **Where the two screens come from.** Two git refs (the redesign is built; the default), or a redesign you build in the copy from their decisions.
- **The decisions**, 1–4 of them, each with a title, a one-line why and the pieces it changes. Draft them from what they said, the PR description or the commits between the refs, and confirm the list.

### 3. Pick the screen and the name

- **Screen:** if the person didn't name one, pick the app's main or home screen and say which.
- **Name:** use the person's first name for the labelled cursor if you know it.
  Otherwise use the first word of `id -F`. The output name is `<App>-<Screen>`.

### 4. Copy the project

```bash
WORK="${TMPDIR:-/tmp}/swarm-video/<AppName>"
rm -rf "$WORK" && mkdir -p "$WORK"
rsync -a --exclude .git --exclude build --exclude DerivedData --exclude '*.xcresult' <project-root>/ "$WORK/"
```

The project root is the folder holding the `.xcodeproj`, `.xcworkspace`,
`project.yml` or `Package.swift`. If the project refers to files outside that
folder (`../Shared`, local packages), copy the common parent instead.

**Before → After from two git refs:** the copy is the *new* design and
`$WORK-before` is the old one, both pulled out read-only. Don't check out,
stash or reset in the real repo. If the new ref is the working tree as it is
now, the rsync above is the copy; for any other ref, or to leave uncommitted
edits out, archive it instead:

```bash
rm -rf "$WORK-before" && mkdir -p "$WORK-before"
git -C <project-root> archive <old-ref> | tar -x -C "$WORK-before"
# only if the new design isn't the current working tree:
rm -rf "$WORK" && mkdir -p "$WORK" && git -C <project-root> archive <new-ref> | tar -x -C "$WORK"
```

**Before → After from decisions:** the rsync copy is the old design; there's
no `$WORK-before`.

### 5. Add the engine

`SKILL_DIR/engine/SwarmKit.swift` is the whole engine: one self-contained
file, no dependencies. Get it into the app target in the copy:

| Project kind | How |
|---|---|
| Xcode 16+ folders (`PBXFileSystemSynchronizedRootGroup` in `project.pbxproj`) | copy the file into the app's source folder |
| XcodeGen (`project.yml`) | copy it into a source folder, then run `xcodegen generate` |
| Swift Package / Tuist | copy it into the app target's sources |
| Classic groups (anything else) | append its contents to the end of the target screen's `.swift` file, and move its `import` lines to the top (no duplicates) |

### 6. Make the app open straight on the screen

In the copy, change the `App`'s root so it shows the target screen directly,
with demo data and any environment objects it needs. Skip launch gates,
splash screens, auth and paywalls. If the screen lives in a `TabView` or
`NavigationStack`, keep that chrome so it looks real.

### 7. Wire the build

**Before → After:** read `SKILL_DIR/reference/choreography.md`, then
`SKILL_DIR/reference/decisions.md`, and follow the second one. First take the
reference screenshots, with `still.py --at 99 --out <file>` on a plain build
(the swarm arguments are ignored by an app without the engine):

- **Two git refs:** build the old ref in `$WORK-before` (given the same step 6 treatment) → `real-before.png`, and the new one in `$WORK` → `real-after.png`.
- **From decisions:** build `$WORK` as it is after step 6 → `real-before.png`. There is no real After: the new design is what you implement in the morph screen, keeping the app's own fonts, colours and components, and only what the confirmed decisions say.

Then build the morph screen in `$WORK`, write `$WORK/decisions.json`, and
skip to step 8.

**Build:** read `SKILL_DIR/reference/choreography.md` first. It has the moves, the
timing, the patterns (cards, repeated rows, images, the joke fix) and the
gotchas.

1. On the screen's root view: `@State private var build = <Screen>Build.make()` and `.swarmStage(build)`.
2. Tag every piece visible on the first screen with `.swarm("id")`.
   - Anything visible that isn't tagged shows from the first frame, so tag it or let it be the page itself.
   - Don't tag what's below the fold.
3. Write `<Screen>Build.make()`: the steps (id, cursor, start, length, move), `SwarmBuild.crew(named: "<FirstName>")`, and `length` ≈ 10.5–11.2 s.

Without `-swarm` the screen opens finished, so normal launches are unaffected.

### 8. Build for the simulator

```bash
cd "$WORK"
xcodebuild -list                      # find the scheme
xcodebuild -project <App>.xcodeproj -scheme <Scheme> -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$WORK/build" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
APP=$(find "$WORK/build/Build/Products" -maxdepth 2 -name '*.app' -path '*iphonesimulator*' | head -1)
```

Use `-workspace <App>.xcworkspace` instead if there is one (CocoaPods).

### 9. Check stills before recording

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

**Before → After** checks instead:

- **0.3 s** must be the *old* screen, complete. Check it against the real one: `python3 "$SKILL_DIR/scripts/compare.py" still-0.3.png real-before.png`.
- **99** must be the *new* screen: `compare.py still-99.png real-after.png`. Both should say `match` (SSIM ≥ 0.985). If not, look at the red in the strip it writes. Usually a stand-in or slot is the wrong size.
- **From decisions** there's no `real-after.png`: check the 99 still yourself against each confirmed decision, and that nothing else changed.
- **Each decision's middle** should show its note card, the pin on the right piece, and the change mid-way (strike, pill, ghost).
- No note card covers its own change. If one does, set its `place:`.

Take single-moment stills for compare.py: `still.py --at 0.3 --out still-0.3.png`.

### 10. Record and render

```bash
python3 "$SKILL_DIR/scripts/record.py" --app "$APP" --seconds <length + 2.5> --out "$WORK/takes" --name take
python3 "$SKILL_DIR/scripts/render.py" "$WORK/takes/take.mov" --out ~/Movies/Swarm/<App>-<Screen>
```

- **record.py** launches the screen as an empty page, starts recording, then cues the build. No launch animation ends up in the take.
- **render.py** finds the first and last movement on its own, cuts from just before the first cursor to a held final frame (12 s by default, `--duration` to change), and writes the mockup, the bare screen and a contact sheet.
- Add `--dark` to record.py for dark-mode screens, and `--args "..."` for any demo-mode flags the copy needs.
- Add `--vertical` to render.py for a 9:16 copy as well.

**Before → After** records longer before the cue, so the old screen gets its
hold, and renders in decisions mode:

```bash
python3 "$SKILL_DIR/scripts/record.py" --app "$APP" --seconds <length + 2.5> --settle 3 --out "$WORK/takes" --name take
python3 "$SKILL_DIR/scripts/render.py" "$WORK/takes/take.mov" --mode decisions \
  --decisions "$WORK/decisions.json" --out ~/Movies/Swarm/<App>-<Screen>-decisions
```

It holds the Before for 1.8 s and the After for 1.6 s, then shows the end card
for 3.2 s (`--before-hold`, `--after-hold`, `--card` to change). The end card
needs `swift`, which comes with Xcode.

### 11. Look, then deliver

Read `<name>-sheet.png`. For **Before → After**, check that it opens on the
old screen labelled Before, takes the decisions one at a time with a readable
note each, lands on the new screen labelled After, and that the end card
(`<name>-compare.png`) lists the decisions in the order the pins were
numbered. Then deliver the videos, the compare still, the decisions, and
whether the After is shipped code (two refs) or your implementation in the
copy.

For **Build**, check:

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
| Before → After: compare.py says the first frame is different | A stand-in, slot or `due` view is taking room in the Before. Match the old sizes exactly, and keep new pieces out of the layout until `due`. |
| A moved piece vanishes mid-flight | It's flying under later siblings. Give its container `.zIndex(1)`. |
| A moved piece starts at its new place in the Before | Its stand-in id doesn't match `.move(from:)`, or the stand-in isn't on screen. |
| A note card covers the change | Pass `place: .top` or `.bottom` on that `.comment`. |
| render.py warns there's not enough Before | Record with a longer `--settle`. |
