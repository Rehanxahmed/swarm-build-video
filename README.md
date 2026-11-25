# Swarm build video: a Claude Code skill

Point Claude at a SwiftUI app and ask for a swarm video. It makes a
12-second clip where four Figma-style multiplayer cursors build one of your
screens live:

- red guides
- grey boxes that turn into cards
- headlines typed and stepped up
- rows alt-dragged into place
- one typo fixed at the end

The clip comes out in a phone mockup, ready to post.

It can also make a **Before → After** film for design decisions (about 19
seconds). The screen opens on your old design. For each decision, a cursor
drops a comment pin saying what's wrong, and another one fixes it:

- strikes out the old piece and removes it
- draws the new one in
- restyles with an inspector pill (`32 pt → 44 pt`)
- drags a piece to its new place

It lands on your real new screen, then shows an end card with both screens
side by side and the decisions listed.

And a **Demo** film (10–20 seconds) shows your app working. A UI test taps
through a real flow on the simulator, each touch shows as a dot, and a
caption pill under the phone says what each step does. It ends on a strip of
key frames with the captions numbered. Already have a screen recording? It
puts that in the mockup with captions instead. Demo works for UIKit apps too.

## Install

You need a Mac with Xcode (plus an iOS Simulator runtime), ffmpeg
(`brew install ffmpeg`) and Claude Code.

```bash
git clone https://github.com/Rehanxahmed/swarm-build-video ~/.claude/skills/swarm-build-video
```

Restart Claude Code if it was open.

## Use

Open Claude Code in your app's folder and say something like:

> make a swarm video of my home screen

or

> make a before/after video of my home screen, from tag v1 to now

or

> make a demo video of logging water and starting a workout

For a before/after, Claude asks where the two designs come from: two git
refs (the redesign is already built), or the decisions you describe, which
it then builds in the copy. It also confirms the list of decisions, 1–4 of
them. Both ends of the film are checked against screenshots of the real
screens.

Claude works on a copy of your project; your real code isn't changed. The
videos land in `~/Movies/Swarm/`:

- `<App>-<Screen>.mp4`: the phone mockup, 1440×1800, 60 fps
- `<App>-<Screen>-screen.mp4`: the bare screen
- for a before/after: `<App>-<Screen>-decisions-compare.png`, the end card as a still
- for a demo: `<App>-<Feature>-strip.png`, the key frames with their captions
- ask for a vertical version to also get a 1080×1920 `-9x16.mp4`

The first run creates a simulator called "Swarm Recorder" and takes a few
extra minutes. Your everyday simulator isn't used.

## What's inside

| File | What it is |
|---|---|
| `SKILL.md` | the steps Claude follows |
| `reference/choreography.md` | how a good build is timed and staged |
| `reference/decisions.md` | how a Before → After film is staged |
| `reference/demo.md` | how a Demo flow is written, paced and captioned |
| `flow/` | the Demo film's flow runner: a UI-test project that drives your app by its bundle id |
| `scripts/record_flow.py` | records a Demo flow on its own simulator |
| `engine/SwarmKit.swift` | the animation engine: one drop-in SwiftUI file |
| `scripts/still.py` | freezes the build at chosen moments, for checking |
| `scripts/record.py` | records the build on its own simulator |
| `scripts/render.py` | auto-cuts the take and renders the mockup video (`--mode decisions` for Before → After, `--mode demo` for Demo) |
| `scripts/card.swift` | draws the labels, caption pills and end cards' text |
| `scripts/compare.py` | checks the film's first and last frames against the real screens |
| `assets/` | the phone frame and backdrop |

Build and Before → After work with SwiftUI screens on iOS 17+. Demo works
with any iOS 17+ app.
