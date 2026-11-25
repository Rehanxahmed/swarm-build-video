# Making a Demo film

The Demo film shows the app *working*: a real flow, tapped through on the
simulator, in the same phone mockup as the other films. Each finger shows as
a soft dot, a caption pill under the phone says what the viewer is looking
at, and the film ends on a strip of key frames with the captions numbered
under them.

Nothing is built or faked here. The app runs as it is; a UI test does the
tapping.

## Two ways in

| Source | What you do | When |
|---|---|---|
| **Scripted flow** (default) | write the flow as a UI test; `record_flow.py` records it | you have the code, and want a clean, repeatable take |
| **Their own recording** | they hand you a screen recording; you time the captions | no code, a flow that's hard to script, or a recording they already like |

For their own recording, skip to [Captions for a recording](#captions-for-a-recording).

## The flow

Agree on it first, in a few lines, with the person:

- **The story:** 2–4 beats, each one thing the feature does. "Log water in one tap. Start a workout from the top of Today. See it live. It lands in your day."
- **The captions:** one per beat, under 40 characters, saying what it does for the person ("Log water in one tap"), not what the finger does ("Tap the plus button").
- **The data:** what has to be on screen for it to look lived in. Seed it in the copy.

Aim for 10–20 s of flow. Every beat costs about 3 s once the taps and pauses
are in.

## Wiring

1. **Touches.** Add the engine (SKILL.md step 5) and one line on the app's root view:

   ```swift
   WindowGroup { ContentView().swarmTouches() }
   ```

   UIKit app: call `SwarmTouches.install()` after the window is made visible
   (end of `scene(_:willConnectTo:options:)`). It only does anything with
   `-swarm-touches`, which `record_flow.py` passes.

2. **The flow.** Copy the runner and write `Flow.swift`:

   ```bash
   rm -rf "$WORK-flow" && cp -R "$SKILL_DIR/flow" "$WORK-flow"
   ```

   Edit only `$WORK-flow/Flow/Flow.swift`. Don't touch `SwarmDemo.swift` or
   the project. The runner is its own little project and drives the app by
   its bundle id, so the app's project never gets a test target.

```swift
import XCTest

final class Flow: XCTestCase {
    func testFlow() throws {
        let app = SwarmDemo.start()            // app up front, waits for the cue
        SwarmDemo.pause(0.8)                    // a beat on the first screen

        SwarmDemo.caption("Log water in one tap")
        app.buttons["Add a glass"].tapWhenReady()
        SwarmDemo.pause(0.6)
        app.buttons["Add a glass"].tap()
        SwarmDemo.pause(1.0)

        SwarmDemo.caption("Start a workout from the top of Today")
        app.buttons["Start workout"].tap()
        SwarmDemo.pause(1.0)
        app.staticTexts["Outdoor run"].tapWhenReady()

        SwarmDemo.caption("Time, distance and heart rate, live")
        SwarmDemo.pause(3.0)
        app.buttons["End workout"].tap()

        SwarmDemo.caption("The workout lands in your day")
        SwarmDemo.pause(2.0)                    // the last screen, held
        SwarmDemo.end()
    }
}
```

| Helper | What it does |
|---|---|
| `SwarmDemo.start()` | brings the app up front, tells the recorder it's ready, waits for the cue. Returns the `XCUIApplication` |
| `SwarmDemo.caption("…")` | shows this caption under the phone from now until the next one |
| `SwarmDemo.pause(s)` | waits, so the viewer can take in what happened (default 0.8 s) |
| `SwarmDemo.end()` | marks the end of the flow; the film stops shortly after |
| `element.tapWhenReady()` | waits up to 10 s for the element, then taps it. Use it after anything that opens a new screen |

Anything XCUITest can do works: `typeText`, `swipeUp()`, `press(forDuration:)`,
`adjust(toPickerWheelValue:)`, alerts. A `swipeUp()` is a quick flick: the dot
jumps a short way and the content carries on with momentum. For a drag the
viewer can follow, use
`a.press(forDuration: 0.1, thenDragTo: b)` between two elements or coordinates.

## Finding elements

- **By the text on it:** `app.buttons["Start workout"]`, `app.staticTexts["Outdoor run"]`.
- **A list row whose button has two lines of text** gets both lines as its label ("Outdoor run, GPS, pace and splits"). Tap its title with `app.staticTexts["Outdoor run"]` instead.
- **Icon-only buttons** have no text. Give them `.accessibilityLabel("Add a glass")` in the copy, or `.accessibilityIdentifier("addGlass")`, and use that.
- **Not sure what's there?** Put `print(app.debugDescription)` in the flow, run it by hand once (below), and read the tree in the log.

## Pacing

- **A tap takes about a second.** XCUITest waits for the app to settle after each one. Put each caption *before* the tap it describes, and it shows a moment before the finger lands.
- **Pause after every change** the viewer should notice: 0.6 s for a small one (a number going up), 1–1.5 s for a new screen, 2–3 s for something live (a timer, a chart filling).
- **End on a pause** of about 2 s. The last screen is what people remember.
- **Typing** with `typeText` is fast. For something a person should read, type it in two or three pieces with `pause(0.3)` between.

## Trying the flow without recording

Run it on the recorder's simulator. With no `SWARM_APP` set, `start()`
launches the app itself, so pass the bundle id once:

```swift
let app = SwarmDemo.start(bundleId: "com.example.myapp")
```

```bash
xcrun simctl install "Swarm Recorder" "$APP"
xcodebuild test -project "$WORK-flow/SwarmFlow.xcodeproj" -scheme SwarmFlow \
  -destination 'platform=iOS Simulator,name=Swarm Recorder' CODE_SIGNING_ALLOWED=NO
```

`record_flow.py` sets `SWARM_APP` itself, so the fallback does no harm when
you leave it in.

## Recording and rendering

```bash
python3 "$SKILL_DIR/scripts/record_flow.py" --app "$APP" --flow "$WORK-flow" --out "$WORK/takes" --name flow
python3 "$SKILL_DIR/scripts/render.py" "$WORK/takes/flow.mov" --mode demo \
  --captions "$WORK/takes/flow.json" --out ~/Movies/Swarm/<App>-<Feature>
```

`record_flow.py` builds the flow, launches the app with `-swarm-touches`, runs
the flow, and only starts recording once the app is up front, so there's no
test runner or app switch in the take. It writes the take and `flow.json`, the
captions timed against it. If the flow fails part way, it says which step and
keeps the take up to there. The full test log is `flow-xcodebuild.log` next to
the take.

`render.py --mode demo` cuts from just before the first tap to the end of the
flow and writes:

- `<name>.mp4`, the mockup with the caption pills, then a 4 s end card (`--card` to change, `--card 0` to leave it off)
- `<name>-screen.mp4`, the bare screen, touches included
- `<name>-strip.png`, the end card as a still: up to 4 frames, one from each caption's part, numbered with its caption
- `<name>-sheet.png`, plus `<name>-9x16.mp4` with `--vertical`

Add `"title": "New in 2.4"` to the captions file to change the end card's
heading (default "What it does").

## Captions for a recording

Their own recording (`.mov` or `.mp4`, from the simulator or a phone) goes
straight to `render.py`. Watch it, note when each beat starts, and write the
captions file yourself:

```json
{"title": "What it does",
 "captions": [{"at": 1.2, "text": "Log water in one tap"},
              {"at": 4.8, "text": "Start a workout from the top of Today"}],
 "end": 14.5}
```

`at` and `end` are seconds into the recording. `end` is optional: without it
the film runs to the last movement plus a 1.2 s hold. A recording with a
different shape from the mockup's screen is scaled to fill it and cropped at
the edges.

A phone recording has no touch dots (iOS can't record them). Say so, and
offer the scripted flow if the taps matter.

## Gotchas

- **The dots come from the app**, so they don't show over the keyboard or system sheets (share sheet, permission prompts). Taps there still work.
- **Permission prompts** mid-flow: grant them before recording, `xcrun simctl privacy "Swarm Recorder" grant <service> <bundle-id>`, so the take doesn't stop on one.
- **Time-based content** (clocks, "just now", timers) changes every run. That's fine: it's real.
- **A flow that fails on the first try** is usually a selector. Read the first `error:` line `record_flow.py` prints, then check the tree with `print(app.debugDescription)`.
