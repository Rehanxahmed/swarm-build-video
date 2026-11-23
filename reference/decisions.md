# Choreographing a Before → After film

The film works when each design decision reads as one small story: a teammate
drops a comment saying what's wrong, another one fixes it, and the screen
ends up as the real new design. The screen opens on the old design, held long
enough to take in, and closes on an end card with the two side by side.

Read `choreography.md` too. The cursors, timing and gotchas are the same
engine; this file covers what's different.

## Where the two screens come from

Both ends of the film must be real. Pick the source with the person:

| Source | Before | After | When |
|---|---|---|---|
| **Two git refs** (default) | the screen at an old commit/tag/branch | HEAD (or a branch) | the redesign is already built |
| **Redesign from decisions** | the screen as it is now | what you build in the copy from the person's decisions | pitching a change, a case study before it ships |

For two refs, work in a copy of the *new* ref, and pull the old one out
read-only. Never check out, stash or reset in the person's repo:

```bash
git -C <project-root> archive <old-ref> | tar -x -C "$WORK-before"
```

For a redesign from decisions, say clearly when you deliver that the After is
your implementation in the copy, not shipped code.

## The decisions

Get 1–4 decisions. Fewer is better: each takes about 2.5 s on screen. Pull
them from what the person says, a PR description or the commit messages
between the refs, and confirm the list with them. Each one needs:

- a **title** for the end card ("Start workout moved to the top")
- a **why**, one line, with numbers if there are real ones ("#A1A1A6 was 2.6:1 on white")
- a **comment**, the note a teammate would leave, under 15 words
- the **pieces** it changes, and how (remove, add, restyle, move)

Write the end card's text to `$WORK/decisions.json`:

```json
{"title": "What changed",
 "decisions": [{"title": "Start workout moved to the top", "why": "The main action sat under everything else"}]}
```

Never invent numbers or research findings for a "why". If there isn't a real
one, describe the change plainly.

## The morph screen

Build one version of the screen in the copy that holds both designs. Start
from the new screen's code and keep the old pieces alive until their decision
replaces them. Unlike the build film, **untagged things show from the first
frame**. That's what you want here: everything that doesn't change is
untagged.

| Change | Old piece | New piece |
|---|---|---|
| Remove | `.erase` step; wrap it in `if !build.gone("id")` so the gap closes | nothing |
| Add | nothing | wrap it in `if build.due("id")` so room opens, then build it with `.draw`, `.type`, `.pop` (like the build film) |
| Restyle (colour, size, weight, radius, copy) | the same view: pick values with `build.after("id")` | `.restyle(from:to:)` step on one representative view |
| Move | an invisible stand-in, same size, at the old place: `if !build.after("id") { oldView.opacity(0).swarm("id.was") }` | the view at its new place, `.move(from: "id.was")` step |

Animate the layout changes so things slide rather than jump. Put these on the
container:

```swift
.animation(.snappy(duration: 0.4), value: build.gone("link"))
.animation(.snappy(duration: 0.4), value: build.due("cta"))
.animation(.snappy(duration: 0.35), value: build.after("buttons"))
```

Without `-swarm`, the build reads as finished: `after` and `gone` are true,
`due` is true, so a normal launch of the copy shows the After screen.

## Moves for decisions

| Move | What the viewer sees | Length |
|---|---|---|
| `.comment("text", on: "id", place:)` | a pin pops onto the piece, a note card opens in the half of the screen away from it, folds back into the pin when the next comment starts | 0.6 |
| `.erase` | selected, struck through in red, shrinks away | 0.8 |
| `.restyle(from: "32 pt", to: "44 pt")` | selected; a dark inspector pill shows the old value, then strikes it and shows the new one. The view changes at the halfway point | 1.1–1.3 |
| `.move(from: "id.was")` | selected at the old place and dragged to the new one, with a dashed ghost and a distance measure | 1.1–1.3 |

The build film's moves still work, mostly for the pieces a decision adds.

`.comment` details:

- `on:` is the id of the piece the pin goes on. The comment's own id needs no tag.
- The card goes in the half of the screen *away* from the pin, so it doesn't cover the problem. If the change happens in that other half (something moving to the top while the pin is low), pass `place: .bottom` or `place: .top`.
- The card shows the cursor's name (the named cursor is the person) and the note's number, which matches the end card.
- Write it as the teammate would, in the person's voice: "32 pt buttons miss the 44 pt minimum tap target." Not "Decision 3: tap targets".

## Timing

- **Length:** 1 decision ≈ 4 s, 4 decisions ≈ 12.5 s of build. The film adds 1.8 s of Before, 1.6 s of After and a 3.2 s end card.
- **One decision at a time.** Its comment, then its change, then the next comment. Don't overlap decisions.
- **Two cursors** are enough: the named one (`you`, 0) makes the comments, another one (1) makes the changes. Use a third only when a decision has parallel parts.
- **Per decision:** comment at `t` (0.6 s), change from `t + 0.8`, next comment about 0.8 s after the change ends.
- **First step at 0.6 s**, like the build film. The Before hold comes from the recording, not from the script.
- The last note closes at wrap (length − 1.05). Pins clear then, too.

## Gotchas

- **A moving piece flies under later siblings.** In a `VStack`, views further down draw on top. Give the moved piece's container `.zIndex(1)`, and the container of any piece whose restyle pill hangs over the next view.
- **A moved piece that changes too** (new words or size): give it a fixed-width slot at the new place sized for its final look, with `.fixedSize()` on the piece inside, and swap the content on `after(id)`. Otherwise it crowds its new neighbours in the Before frame.
- **A restyle that touches many views** (every note, every button): tag one of them with the step and have them all read `build.after(id)`.
- **The Before frame must match the old app exactly.** A slot or stand-in that's the wrong size shifts everything below it. `compare.py` catches this.
- **Comment pins on removed pieces** stay where the piece was, which reads fine, and they clear once the next note opens.

## A whole script (for reference)

A Today screen: v1 had a "Start workout" link at the bottom, faint notes,
32 pt header buttons and a streak chip under the cards. v2 has a big Start
button at the top, darker notes, 44 pt buttons and the streak in the header.
About 12.8 s of build.

```swift
enum TodayDecisions {
    static func make() -> SwarmBuild {
        typealias S = SwarmBuild.Step
        let you = 0, a = 1
        return SwarmBuild(steps: [
            // 1 · the main action moves to the top
            S("note.1", cursor: you, at: 0.6, for: 0.6, .comment("Start workout is the main action, but it sits under everything else.", on: "link")),
            S("link", cursor: a, at: 1.5, for: 0.8, .erase),
            S("cta", cursor: a, at: 2.9, for: 0.9, .draw(radius: 16)),
            S("cta.label", cursor: you, at: 3.6, for: 0.6, .type(grow: false)),
            // 2 · notes readable
            S("note.2", cursor: you, at: 4.6, for: 0.6, .comment("Notes in #A1A1A6 are 2.6:1 on white. Hard to read outside.", on: "notes")),
            S("notes", cursor: a, at: 5.4, for: 1.2, .restyle(from: "#A1A1A6", to: "#3C3C43")),
            // 3 · tap targets
            S("note.3", cursor: you, at: 7.0, for: 0.6, .comment("32 pt buttons miss the 44 pt minimum tap target.", on: "buttons")),
            S("buttons", cursor: a, at: 7.8, for: 1.2, .restyle(from: "32 pt", to: "44 pt")),
            // 4 · the streak goes where people look first
            S("note.4", cursor: you, at: 9.4, for: 0.6, .comment("The streak keeps people coming back. Put it up top.", on: "streak.was", place: .bottom)),
            S("streak", cursor: a, at: 10.2, for: 1.2, .move(from: "streak.was")),
        ], cursors: SwarmBuild.crew(named: "Sam"), length: 12.8)
    }
}
```

And the parts of the view that carry both designs:

```swift
var soft: Color { build.after("notes") ? Color(white: 0.24) : Color(white: 0.63) }
var big: Bool { build.after("buttons") }

VStack(alignment: .leading, spacing: 18) {
    HStack(alignment: .firstTextBaseline) {
        titleBlock
        Spacer()
        streak(compact: build.after("streak"))      // new place, old words until it lands
            .fixedSize()
            .swarm("streak")
            .frame(width: 48)
        HStack(spacing: 8) { iconButton("bell"); iconButton("gearshape") }
            .swarm("buttons")
    }
    .zIndex(1)                                      // the streak flies over the cards

    if build.due("cta") {                           // room opens, then it's drawn
        Text("Start workout").swarm("cta.label")
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 16).fill(.blue).swarm("cta"))
    }

    ForEach(stats) { StatCard(stat: $0, note: soft) }   // first card's note tagged "notes"

    if !build.after("streak") {                     // old place keeps its room
        streak(compact: false).opacity(0).swarm("streak.was")
    }
    if !build.gone("link") {                        // the old link, until erased
        Text("Start workout  →").swarm("link")
    }
}
.animation(.snappy(duration: 0.4), value: build.gone("link"))
.animation(.snappy(duration: 0.4), value: build.due("cta"))
.animation(.snappy(duration: 0.35), value: big)
.animation(.snappy(duration: 0.35), value: build.after("streak"))
```
