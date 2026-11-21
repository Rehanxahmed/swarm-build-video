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

Claude works on a copy of your project; your real code isn't changed. The
videos land in `~/Movies/Swarm/`:

- `<App>-<Screen>.mp4`: the phone mockup, 1440×1800, 60 fps
- `<App>-<Screen>-screen.mp4`: the bare screen

The first run creates a simulator called "Swarm Recorder" and takes a few
extra minutes. Your everyday simulator isn't used.

## What's inside

| File | What it is |
|---|---|
| `SKILL.md` | the steps Claude follows |
| `reference/choreography.md` | how a good build is timed and staged |
| `engine/SwarmKit.swift` | the animation engine: one drop-in SwiftUI file |
| `scripts/still.py` | freezes the build at chosen moments, for checking |
| `scripts/record.py` | records the build on its own simulator |
| `scripts/render.py` | auto-cuts the take and renders the mockup video |
| `assets/` | the phone frame and backdrop |

Works with SwiftUI screens on iOS 17+. UIKit screens aren't supported.
