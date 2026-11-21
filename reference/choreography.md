# Choreographing a swarm build

The film works when it reads like four people building a design file
together: guides first, then structure, then content, with repeated things
copied rather than rebuilt and one human slip fixed at the end. The script is
just timed steps, but these rules make the difference between that and
things blinking on.

## The API (SwarmKit.swift)

```swift
@State private var build = HomeBuild.make()

var body: some View {
    content
        .swarmStage(build)          // ROOT of the screen: cursors on top, starts the clock
}

Text("Today").swarm("card.title")   // a piece: its id must match a step
```

```swift
enum HomeBuild {
    static func make() -> SwarmBuild {
        typealias S = SwarmBuild.Step
        return SwarmBuild(steps: [
            S("guide.left", cursor: 3, at: 0.6, for: 0.47, .guide(vertical: true)),
            S("title",      cursor: 1, at: 0.75, for: 1.0, .type(grow: true)),
            // …
        ], cursors: SwarmBuild.crew(named: "Sam"), length: 10.8)   // wrap = length − 1.05 by default
    }
}
```

Reading the clock from your own views. Get the build with
`@Environment(SwarmBuild.self) private var build: SwarmBuild?`, or pass it
down:

| Call | Use |
|---|---|
| `build.amount("id")` | 0…1 through that step (0 before the build, 1 when done or if the id is unknown) |
| `build.typo("id")` | true until the `.edit` step `id` selects the text. Show the wrong words while it's true |
| `build.stale("id")` | true while the `.duplicate` copy `id` still shows its original's content |
| `build.pin("guide.left", x: 20, y: 300)` | where a guide stops (x for vertical, y for horizontal); y/x is where the cursor holds it |
| `build.park("c.away", at: CGPoint(...))` | a `.trace` step's spot: moves a finished cursor out of the way |

Call `pin` and `park` in an `.onAppear` on the screen's root. The build
starts later, so the order doesn't matter.

## Moves

| Move | What the viewer sees | Use for | Length |
|---|---|---|---|
| `.guide(vertical:)` | red line slides in from the screen edge with its cursor, fades at wrap | margins (pin to x = page margin) | 0.45–0.55 |
| `.draw(radius:)` | crosshair drag of a grey box with handles and "W × H" pill, then it restyles into the view (radius = the view's corner radius) | cards, panels, buttons, image boxes, chips | 0.8–1.0 (small: 0.6) |
| `.type(grow: true)` | typed at 40 % size behind a caret, then four clicks up to full size | headlines, card titles | 0.95–1.05 |
| `.type(grow: false)` | typed at size | body lines, labels, numbers | 0.45–0.7 |
| `.pen` | revealed left to right with two pen nodes | dividers, dotted rules, chart lines, progress tracks | 0.5–0.65 |
| `.pop` | dropped in with a click and an overshoot | icons, glyphs, avatars, small buttons | 0.35–0.42 |
| `.duplicate(dx:)` | alt-dragged copy slides from `dx` (the original's offset, usually negative) with a red measure, then gets selected and retyped | 2nd/3rd column, sibling stats, tiles in a row | 0.55–0.65 |
| `.duplicateDown(dy:)` | same, downward (`dy` = −row pitch) | list rows, stacked cards | 0.6–0.66 |
| `.edit` | double-click, select, retype | the joke fix (one per film) | 0.85–0.9 |
| `.fade` | plain fade, no marks; use with cursor −1 | groups that can't be built piece by piece, chart bodies, decorations | 0.3–0.5 |
| `.trace` | cursor follows a path (`park`) | getting a finished cursor out of the way | 0.5–0.6 |
| `.lift` | press and pull up | something rising (rare) | 0.6 |

## Timing rules

- **Length:** 10.5–11.2 s of build gives a 12 s film, with ~0.45 s of empty page before and a beat of finished screen after.
- **Nothing before 0.6 s.** Every cursor glides in from its edge (0.55 s lead) instead of popping in halfway.
- **Four cursors, no more.** Cursor 0 is blue and named; 1 purple, 2 green, 3 orange. They come from right-upper, left-upper, left-lower and right-lower.
- **Two or three cursors busy at once.** Steps on different cursors overlap freely.
- **One cursor, one thing at a time.** Leave ≥ 0.2 s between the end of one of its steps and the start of its next (travel time grows with distance; ~0.4 s for a long trip).
- **Top to bottom, outside in:** guides → header → hero → cards (box first, then title, then contents) → buttons → the fix.
- **The joke fix** starts around length − 2.2 s and gets the stage to itself. Park cursors that are finished near it (`park` + `.trace`) so the viewer watches the fix.
- **Wrap** (default length − 1.05): guides fade and cursors head home one after another.

## Patterns

### Cards: tag the background, not the card

`.draw` on the card itself would fade its children in with it. Instead put the
step on the card's background shape, so the contents can be built separately:

```swift
VStack { … }                        // contents tagged on their own
    .padding(16)
    .background {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.white)
            .swarm("card")            // .draw(radius: 24)
    }
```

### Repeated rows and columns: build one, copy the rest

Build the first item piece by piece (or as one `.pop`/`.type`). Then each
next item is a `.duplicate` / `.duplicateDown` that slides in from the
previous one and shows the previous one's content until it's retyped:

```swift
ForEach(items.indices, id: \.self) { i in
    let shown = i > 0 && (build?.stale("row.\(i)") ?? false) ? items[i - 1] : items[i]
    RowView(item: shown)
        .swarm("row.\(i)")
}
// steps: row.0 .pop or built from parts; row.1 .duplicateDown(dy: -rowPitch); row.2 …
```

`dx`/`dy` is the distance back to the original: minus the column width plus
spacing, or minus the row height plus spacing. Measure from the layout
constants. If you get it wrong the copy slides in from the wrong place.

For a first item made of parts (icon well, icon, text), tag only the first
item's parts: `.swarm(ifSome: i == 0 ? "well.0" : nil)`.

### Images and illustrations

Draw a grey box (`.draw(radius: 0)` or the image's corner radius) and the
image appears as the box restyles. Tag the image view itself.

### The joke fix

Pick one visible word and a plausible, funny wrong version: "Uncle's cat" for
"Uncle's car", "Start a nap" for "Start a walk", "Good morming", "T-plus" for
"T-minus", "Running late" for "On time". It's typed wrong as part of the build
and fixed near the end:

```swift
Text(build.typo("title.edit") ? "Good morming" : "Good morning")
    .swarm("title.edit")      // inner: the .edit step
    .swarm("title")           // outer: the .type step that first types it
```

### Guides

One or two vertical guides at the page margins, first thing, by the same
cursor:

```swift
.onAppear {
    let w = UIScreen.main.bounds.width
    build.pin("guide.left", x: 20, y: 300)
    build.pin("guide.right", x: w - 20, y: 470)
}
```

### Things you can't tag piece by piece

Charts, maps, complex custom drawing: draw a grey box for the area and
`.fade` the content (cursor −1) right after. Or read `build.amount("id")` in
your own view to animate it (e.g. a chart line growing with `amount`).

### Numbers

Type them (`.type(grow: false)`); for a row of stats type the first and
duplicate the rest.

## Gotchas

- **`Group { … }.swarm(id)`** applies to each child separately and stacks them. Wrap in a `VStack`/`ZStack`.
- **Ids are case-sensitive and must be unique.** An id that isn't in the steps means "finished": that view shows from the first frame.
- **Two `.swarm` on one view** is fine (edit inside, type outside), but the outer one controls visibility.
- **Off-screen pieces** have no frame and pull their cursor to the corner. Only build what's on the first screen.
- **System chrome** (status bar, tab bar, toolbars, large navigation titles) can't be built. It's present from the first frame, which is fine. If the title matters, use a custom header in the copy.
- **Lazy lists** only create visible rows. Fine, since you only build visible ones.
- **Your app's own appear animations** still run on launch, before the cue. They're finished by the time recording starts.
- **Fonts and sizes** stay the app's own. Never restyle the screen for the film.

## A whole script (for reference)

A home screen with a title, a status line, a hero image, three stats, a card
with three rows and a button. About 10.6 s.

```swift
enum HomeBuild {
    static func make() -> SwarmBuild {
        typealias S = SwarmBuild.Step
        let you = 0, a = 1, b = 2, c = 3, nobody = -1
        let column = -(UIScreen.main.bounds.width - 40) / 3      // stat pitch
        return SwarmBuild(steps: [
            // guides, header
            S("guide.left",  cursor: c, at: 0.6,  for: 0.47, .guide(vertical: true)),
            S("guide.right", cursor: c, at: 1.16, for: 0.52, .guide(vertical: true)),
            S("title",       cursor: a, at: 0.75, for: 1.0,  .type(grow: true)),
            S("avatar",      cursor: b, at: 0.9,  for: 0.4,  .pop),
            S("status",      cursor: you, at: 1.4, for: 0.66, .type(grow: false)),
            // hero
            S("hero",        cursor: a, at: 2.0,  for: 1.0,  .draw(radius: 20)),
            // three stats: one typed, two copies
            S("stat.0",      cursor: c, at: 2.1,  for: 0.55, .type(grow: false)),
            S("stat.1",      cursor: c, at: 2.9,  for: 0.6,  .duplicate(dx: column)),
            S("stat.2",      cursor: c, at: 3.7,  for: 0.6,  .duplicate(dx: column)),
            // the card: box, title, rule, first row built, two copied down
            S("card",        cursor: b, at: 3.3,  for: 0.9,  .draw(radius: 24)),
            S("card.title",  cursor: a, at: 4.35, for: 0.95, .type(grow: true)),
            S("card.rule",   cursor: c, at: 4.6,  for: 0.6,  .pen),
            S("row.0.icon",  cursor: b, at: 5.1,  for: 0.4,  .pop),
            S("row.0.text",  cursor: a, at: 5.5,  for: 0.6,  .type(grow: false)),
            S("row.1",       cursor: you, at: 6.2, for: 0.64, .duplicateDown(dy: -60)),
            S("row.2",       cursor: you, at: 7.0, for: 0.64, .duplicateDown(dy: -60)),
            S("card.more",   cursor: nobody, at: 7.5, for: 0.45, .fade),
            // button, typed wrong; finished cursors park; the fix
            S("button",      cursor: b, at: 7.2,  for: 0.8,  .draw(radius: 28)),
            S("button.label", cursor: a, at: 8.0, for: 0.62, .type(grow: false)),
            S("c.away",      cursor: c, at: 7.9,  for: 0.5,  .trace),
            S("a.away",      cursor: a, at: 8.8,  for: 0.55, .trace),
            S("button.edit", cursor: you, at: 8.6, for: 0.88, .edit),
        ], cursors: SwarmBuild.crew(named: "Sam"), length: 10.6)
    }
}
```
