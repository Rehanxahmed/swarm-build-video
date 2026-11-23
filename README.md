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
- ask for a vertical version to also get a 1080×1920 `-9x16.mp4`

The first run creates a simulator called "Swarm Recorder" and takes a few
extra minutes. Your everyday simulator isn't used.

## What's inside

| File | What it is |
|---|---|
| `SKILL.md` | the steps Claude follows |
| `reference/choreography.md` | how a good build is timed and staged |
| `reference/decisions.md` | how a Before → After film is staged |
| `engine/SwarmKit.swift` | the animation engine: one drop-in SwiftUI file |
| `scripts/still.py` | freezes the build at chosen moments, for checking |
| `scripts/record.py` | records the build on its own simulator |
| `scripts/render.py` | auto-cuts the take and renders the mockup video (`--mode decisions` for Before → After) |
| `scripts/card.swift` | draws the Before/After labels and the end card's text |
| `scripts/compare.py` | checks the film's first and last frames against the real screens |
| `assets/` | the phone frame and backdrop |

Works with SwiftUI screens on iOS 17+. UIKit screens aren't supported.
