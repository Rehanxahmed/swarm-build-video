import SwiftUI
import QuartzCore

// MARK: - SwarmKit
//
// A SwiftUI screen builds itself the way a design file gets made. A few
// multiplayer cursors drag guides in, draw grey boxes that turn into cards,
// type the copy, pen the lines and alt-drag copies into place.
//
// The build is a script of timed steps. Every view that takes part is tagged
// with `.swarm("id")` and works out its own look from the clock. So the real
// screen is the thing being built, and there's nothing to swap when the
// script ends.
//
// Wiring, in short:
//
//     @State private var build = MyScreenBuild.make()     // a SwarmBuild
//     var body: some View {
//         content                                         // pieces tagged .swarm("id")
//             .swarmStage(build)                          // on the screen's ROOT view
//     }
//
// Before → After films use the same wiring. Untagged things show from the
// start, old pieces leave with `.erase` (and `gone(_:)`), new ones arrive with
// `due(_:)` and the build moves, restyles read `after(_:)`, and `.comment`
// pins say why. See reference/decisions.md.
//
// Launch arguments:
//     -swarm            play the build (without it the screen opens finished)
//     -swarm-cue        wait for the recorder's cue (Darwin notification
//                       "swarm.start") instead of starting by itself
//     -swarm-at 4.2     freeze the build at 4.2 s, for stills
//
// Needs iOS 17 or later (Observation).

@Observable final class SwarmBuild {
    enum Move {
        /// Crosshair-drag a box (grey, selected, size pill), then it takes on its real look.
        case draw(radius: CGFloat)
        /// Typed left to right behind a caret. `grow` types it small, then steps it up to size.
        case type(grow: Bool)
        /// Stroked left to right with the pen.
        case pen
        /// Dropped in with a click and a little overshoot.
        case pop
        /// Alt-dragged in from `dx` points away (negative = from the left), then retyped.
        case duplicate(dx: CGFloat)
        /// Alt-dragged down from `dy` points above (negative = from above), then retyped.
        case duplicateDown(dy: CGFloat)
        /// Double-clicked, selected and retyped. Pair it with `typo(_:)` for the joke fix.
        case edit
        /// Fades in. No cursor marks.
        case fade
        /// A red guide dragged in from the screen edge to the frame's leading (or top) edge.
        case guide(vertical: Bool)
        /// The cursor follows a path registered with `park(_:at:)` or `paths[id]`.
        case trace
        /// Press and pull upward.
        case lift

        // Before → After films: the screen opens on the old design and the
        // cursors make each decision on it.

        /// Selected, struck through and shrunk away. Visible before its step,
        /// gone after (take it out of the layout with `gone(_:)`).
        case erase
        /// Dragged from where it used to sit to where it sits now, leaving a
        /// dashed ghost behind. `from` is the id of a stand-in at the old place
        /// (an invisible view the same size, tagged `.swarm(from)`), which also
        /// keeps the old layout until `after(_:)` lets it go.
        case move(from: String)
        /// Selected while an inspector pill shows `from → to`. The view itself
        /// changes halfway through: read `after(_:)` to pick the new value.
        case restyle(from: String, to: String)
        /// A comment pin with a note, dropped on the view tagged with this id
        /// (or with `on`, or a `pin` point). The note card opens in the half of
        /// the screen away from the pin, so it never covers the change (`place`
        /// overrides that), stays open until the next comment starts, then
        /// folds into its numbered pin.
        case comment(_ text: String, on: String? = nil, place: VerticalEdge? = nil)
    }

    /// A `.comment` step with its number and when its card folds away.
    struct Note {
        var step: Step
        var text: String
        var number: Int
        var closes: Double
    }

    struct Step {
        var id: String
        /// Index into `cursors`, or -1 for a step nobody visibly does.
        var cursor: Int
        var start: Double
        var length: Double
        var move: Move
        var end: Double { start + length }

        init(_ id: String, cursor: Int, at start: Double, for length: Double, _ move: Move) {
            self.id = id
            self.cursor = cursor
            self.start = start
            self.length = length
            self.move = move
        }
    }

    struct Cursor {
        var color: Color
        var name: String?
        /// Off-screen point it comes from and goes back to, as fractions of the screen.
        var home: UnitPoint

        static let blue = Color(red: 13 / 255, green: 153 / 255, blue: 1)
        static let purple = Color(red: 151 / 255, green: 71 / 255, blue: 1)
        static let green = Color(red: 20 / 255, green: 174 / 255, blue: 92 / 255)
        static let orange = Color(red: 1, green: 138 / 255, blue: 31 / 255)
    }

    /// The usual crew: four cursors coming in from all four sides, the first
    /// one blue and carrying a name tag.
    static func crew(named name: String) -> [Cursor] {
        [Cursor(color: Cursor.blue, name: name, home: UnitPoint(x: 1.15, y: 0.3)),
         Cursor(color: Cursor.purple, name: nil, home: UnitPoint(x: -0.15, y: 0.22)),
         Cursor(color: Cursor.green, name: nil, home: UnitPoint(x: -0.15, y: 0.7)),
         Cursor(color: Cursor.orange, name: nil, home: UnitPoint(x: 1.15, y: 0.8))]
    }

    enum Phase { case pending, running, done }

    /// True when the app was launched with `-swarm`.
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-swarm") }

    let steps: [Step]
    let cursors: [Cursor]
    /// Seconds from the first cursor to the finished screen.
    let length: Double
    /// When the guides let go and the cursors head home.
    let wrap: Double

    private(set) var phase: Phase
    /// Seconds into the build.
    private(set) var time: Double = 0
    /// Bumped once the first layouts are in, so pieces that place themselves
    /// by other pieces' frames (moves) redraw while the screen waits.
    private(set) var settled = 0

    /// Where each tagged view sits on screen, and paths for `.trace` steps.
    @ObservationIgnored var frames: [String: CGRect] = [:]
    @ObservationIgnored var paths: [String: [CGPoint]] = [:]
    /// The whole screen, safe areas included.
    @ObservationIgnored var screen: CGSize = .zero
    /// The `.comment` steps in the order they're made.
    @ObservationIgnored private(set) var notes: [Note] = []
    @ObservationIgnored private let index: [String: Int]
    @ObservationIgnored private var ticker: SwarmTicker?
    @ObservationIgnored private var began: CFTimeInterval = 0
    @ObservationIgnored private var armed = false

    /// `wrap` defaults to one second before the end.
    init(steps: [Step], cursors: [Cursor], length: Double, wrap: Double? = nil, play: Bool = SwarmBuild.enabled) {
        self.steps = steps
        self.cursors = cursors
        self.length = length
        self.wrap = wrap ?? max(0, length - 1.05)
        phase = play ? .pending : .done
        var index: [String: Int] = [:]
        for (i, step) in steps.enumerated() where index[step.id] == nil { index[step.id] = i }
        self.index = index
        let comments = steps.filter { if case .comment = $0.move { true } else { false } }.sorted { $0.start < $1.start }
        notes = comments.enumerated().map { i, step in
            guard case .comment(let text, _, _) = step.move else { fatalError() }
            let next = i + 1 < comments.count ? comments[i + 1].start : self.wrap
            return Note(step: step, text: text, number: i + 1, closes: max(step.end + 0.4, next))
        }
    }

    // MARK: Clock

    func start() {
        guard phase == .pending else { return }
        phase = .running
        began = CACurrentMediaTime()
        ticker = SwarmTicker { [weak self] in
            guard let self else { return }
            let t = CACurrentMediaTime() - self.began
            if t >= self.length { self.finish() } else { self.time = t }
        }
    }

    func finish() {
        ticker?.stop()
        ticker = nil
        phase = .done
    }

    /// Stops the clock at `t` seconds into the build, for stills of any moment.
    func hold(at t: Double) {
        ticker?.stop()
        ticker = nil
        phase = t >= length ? .done : .running
        time = t
        // Frames arrive after the first layout; touch the clock again so the
        // cursors redraw where the pieces really are.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.phase == .running else { return }
            self.time = t + 0.0001
        }
    }

    /// Called by `.swarmStage` once the screen is up: freezes for a still,
    /// waits for the recorder's cue, or just starts.
    func arm() {
        guard !armed, phase == .pending else { return }
        armed = true
        for delay in [0.25, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.settled += 1 }
        }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-swarm-at"), i + 1 < args.count, let t = Double(args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.hold(at: t) }
        } else if args.contains("-swarm-cue") {
            listenForCue()
            // never hang forever on a missed cue
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.start() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.start() }
        }
    }

    /// `xcrun simctl spawn <device> notifyutil -p swarm.start` starts the build.
    private func listenForCue() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let build = Unmanaged<SwarmBuild>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { build.start() }
            },
            "swarm.start" as CFString, nil, .deliverImmediately)
    }

    // MARK: Reading the clock from your own views

    func step(_ id: String) -> Step? { index[id].map { steps[$0] } }

    /// How far through its step a piece is, clamped: 0 until it starts (and
    /// for the whole of a build that hasn't begun), 1 once it's over.
    /// Unknown ids read 1, so untagged things always look finished.
    func amount(_ id: String) -> Double {
        switch phase {
        case .done: return 1
        case .pending: return 0
        case .running:
            guard let step = step(id) else { return 1 }
            return max(0, min(1, (time - step.start) / step.length))
        }
    }

    /// For the joke fix: true until an `.edit` step with this id has selected
    /// the text, so show the wrong words while it's true.
    func typo(_ id: String) -> Bool { amount(id) < 0.45 }

    /// For alt-dragged copies: true while a `.duplicate` step with this id is
    /// still showing the original's content, before it's retyped.
    func stale(_ id: String) -> Bool { phase == .running && amount(id) < 0.66 }

    /// For `.restyle` steps: false while the old look shows, true once the
    /// change lands (halfway through), and true whenever the build isn't playing.
    func after(_ id: String) -> Bool { amount(id) >= 0.5 }

    /// For `.erase` steps: true once the piece has shrunk away, so it can leave
    /// the layout (`if !build.gone("old") { … }`) and the rest closes up.
    func gone(_ id: String) -> Bool { amount(id) >= 1 }

    /// For new things that take up room: true from just before their step
    /// (`lead` seconds), so the layout opens a gap first and the piece is then
    /// built into it (`if build.due("new") { … }`).
    func due(_ id: String, lead: Double = 0.45) -> Bool {
        switch phase {
        case .done: return true
        case .pending: return false
        case .running:
            guard let step = step(id) else { return true }
            return time >= step.start - lead
        }
    }

    /// The rectangle a step works on: its own view, or for a comment the view
    /// it's on.
    func anchor(_ step: Step) -> CGRect? {
        if case .comment(_, let on?, _) = step.move, let f = frames[on] { return f }
        return frames[step.id]
    }

    /// For a `.move`: how far the old place is from the new one (centre to centre).
    func shift(_ step: Step) -> CGSize {
        _ = settled
        guard case .move(let from) = step.move, let was = frames[from], let now = frames[step.id] else { return .zero }
        return CGSize(width: was.midX - now.midX, height: was.midY - now.midY)
    }

    /// Where a comment's pin points, given its anchor.
    static func pinPoint(_ f: CGRect, in size: CGSize) -> CGPoint {
        // top-trailing corner, or top-leading when that would run off the edge
        CGPoint(x: f.maxX + 30 > size.width ? max(4, f.minX - 22) : f.maxX - 4, y: max(f.minY + 4, 56))
    }

    /// Whether an inspector pill for a piece at `f` sits above it (no room below).
    func pillAbove(_ f: CGRect) -> Bool {
        screen.height > 0 && f.maxY > screen.height - 110
    }

    /// Pins a guide (or any step without a view of its own) to a point on
    /// screen. A vertical guide stops at `x`; a horizontal one at `y`.
    func pin(_ id: String, x: CGFloat, y: CGFloat) {
        frames[id] = CGRect(x: x, y: y, width: 0, height: 0)
    }

    /// A `.trace` step that just moves the cursor out of the way and lets it
    /// drift there, so a cursor that's finished doesn't sit on the work.
    func park(_ id: String, at point: CGPoint) {
        paths[id] = [point, CGPoint(x: point.x - 5, y: point.y - 3)]
    }

    // MARK: Cursors

    /// Where a cursor is right now: working a step, travelling to its next
    /// one, or on its way in from (or back out to) its edge of the screen.
    func position(of cursor: Int, in size: CGSize) -> CGPoint {
        let home = CGPoint(x: cursors[cursor].home.x * size.width, y: cursors[cursor].home.y * size.height)
        let mine = steps.filter { $0.cursor == cursor && (anchor($0) != nil || paths[$0.id] != nil) }
        guard let first = mine.first, let last = mine.last else { return home }

        let leave = wrap + Double(cursor) * 0.12
        if time >= leave, time >= last.end {
            // heading home
            let from = spot(last, 1, size)
            return travel(from, home, (time - max(leave, last.end)) / 0.7, bend: 0.1)
        }
        if time < first.start {
            let lead = 0.55
            return travel(home, spot(first, 0, size), (time - (first.start - lead)) / lead, bend: -0.08)
        }
        for (i, step) in mine.enumerated() {
            if time < step.end { return spot(step, (time - step.start) / step.length, size) }
            guard i + 1 < mine.count else { break }
            let next = mine[i + 1]
            if time < next.start {
                let from = spot(step, 1, size), to = spot(next, 0, size)
                let d = hypot(to.x - from.x, to.y - from.y)
                let takes = min(next.start - step.end, max(0.18, min(0.7, 0.14 + sqrt(d) * 0.021)))
                let u = (time - (next.start - takes)) / takes
                if u <= 0 {
                    // waiting: a slow idle drift
                    return CGPoint(x: from.x + CGFloat(sin(time * 2.3 + Double(cursor))) * 2.5,
                                   y: from.y + CGFloat(cos(time * 1.9 + Double(cursor) * 2)) * 2.5)
                }
                return travel(from, to, u, bend: cursor % 2 == 0 ? 0.09 : -0.09)
            }
        }
        return spot(last, 1, size)
    }

    /// A glide from a to b on a shallow arc, eased at both ends.
    private func travel(_ a: CGPoint, _ b: CGPoint, _ u: Double, bend: CGFloat) -> CGPoint {
        let u = max(0, min(1, u))
        let e = CGFloat(u * u * (3 - 2 * u))
        let dx = b.x - a.x, dy = b.y - a.y
        let arc = CGFloat(sin(.pi * Double(e))) * bend
        return CGPoint(x: a.x + dx * e - dy * arc, y: a.y + dy * e + dx * arc)
    }

    /// The cursor's place at a share `p` of a step.
    private func spot(_ step: Step, _ p: Double, _ size: CGSize) -> CGPoint {
        let p = max(0, min(1, p))
        let f = anchor(step) ?? .zero
        switch step.move {
        case .erase:
            // click it, then hold still while it goes
            return CGPoint(x: f.midX + 4, y: f.midY + 3)
        case .move:
            let d = shift(step), e = CGFloat(SwarmCurve.inOut((p - 0.2) / 0.55))
            return CGPoint(x: f.midX + d.width * (1 - e) + 4, y: f.midY + d.height * (1 - e) + 3)
        case .restyle:
            // select the piece, then over to the inspector pill
            let e = CGFloat(SwarmCurve.inOut((p - 0.22) / 0.25))
            let pillY = pillAbove(f) ? f.minY - 17 : f.maxY + 17
            return CGPoint(x: f.midX + 26 * e, y: f.midY + (pillY - f.midY) * e)
        case .comment:
            let at = Self.pinPoint(f, in: size)
            return CGPoint(x: at.x + 3, y: at.y + 2)
        case .draw:
            let e = CGFloat(SwarmCurve.out(min(1, p / 0.5)))
            return CGPoint(x: f.minX + f.width * e, y: f.minY + f.height * e)
        case .type(let grow):
            let scale = grow ? SwarmCurve.grow(p) : 1
            let typed = CGFloat(min(1, p / (grow ? SwarmCurve.typingShare : 1)))
            return CGPoint(x: f.minX + f.width * scale * typed + 3, y: f.maxY - f.height * scale * 0.5)
        case .pen:
            return CGPoint(x: f.minX + f.width * CGFloat(p), y: f.midY)
        case .pop, .fade:
            return CGPoint(x: f.midX + 3, y: f.midY + 3)
        case .duplicate(let dx):
            let e = CGFloat(SwarmCurve.inOut(min(1, p / 0.5)))
            return CGPoint(x: f.midX + dx * (1 - e), y: f.midY + 2)
        case .duplicateDown(let dy):
            let e = CGFloat(SwarmCurve.inOut(min(1, p / 0.5)))
            return CGPoint(x: f.midX + 2, y: f.midY + dy * (1 - e))
        case .edit:
            return CGPoint(x: f.maxX - 6, y: f.midY)
        case .guide(let vertical):
            let e = CGFloat(SwarmCurve.out(p))
            return vertical ? CGPoint(x: f.minX * e, y: f.midY) : CGPoint(x: f.midX, y: f.minY * e)
        case .trace:
            guard let path = paths[step.id], path.count > 1 else { return CGPoint(x: f.midX, y: f.midY) }
            let at = CGFloat(p) * CGFloat(path.count - 1)
            let i = min(path.count - 2, Int(at)), k = at - CGFloat(i)
            return CGPoint(x: path[i].x + (path[i + 1].x - path[i].x) * k, y: path[i].y + (path[i + 1].y - path[i].y) * k)
        case .lift:
            return CGPoint(x: f.midX, y: f.midY + 26 - 52 * CGFloat(SwarmCurve.inOut(p)))
        }
    }
}

enum SwarmCurve {
    static func out(_ x: Double) -> Double { 1 - pow(1 - max(0, min(1, x)), 3) }
    static func inOut(_ x: Double) -> Double {
        let x = max(0, min(1, x))
        return x * x * (3 - 2 * x)
    }
    /// Past the mark and back, for things dropped into place.
    static func back(_ x: Double) -> Double {
        let x = max(0, min(1, x)) - 1, s = 2.2
        return x * x * ((s + 1) * x + s) + 1
    }

    /// Share of a growing text's step spent typing; the rest steps it up to size.
    static let typingShare = 0.58
    /// Typed at 40 %, then four clicks of the size field.
    static func grow(_ p: Double) -> CGFloat {
        guard p >= typingShare else { return 0.4 }
        let stage = min(4, Int((p - typingShare) / (1 - typingShare) * 4.6) + 1)
        return 0.4 + 0.15 * CGFloat(stage)
    }
}

/// A display link that calls back every frame until stopped.
final class SwarmTicker: NSObject {
    private var link: CADisplayLink?
    private let fire: () -> Void

    init(_ fire: @escaping () -> Void) {
        self.fire = fire
        super.init()
        link = CADisplayLink(target: self, selector: #selector(step))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func step() { fire() }

    /// The link holds on to its target, so it has to be told to let go.
    func stop() {
        link?.invalidate()
        link = nil
    }
}

// MARK: - The stage and the pieces

extension View {
    /// Put on the screen's ROOT view: shares the build with every `.swarm`
    /// piece, draws the guides and cursors above everything, and starts the clock.
    func swarmStage(_ build: SwarmBuild) -> some View { modifier(SwarmStage(build: build)) }

    /// Takes part in the build as the step with this id.
    func swarm(_ id: String) -> some View { modifier(SwarmPiece(id: id)) }

    /// `.swarm(id)` when there's an id, nothing otherwise (for the first of a
    /// repeated row that gets built while the others are copied).
    func swarm(ifSome id: String?) -> some View { modifier(SwarmMaybe(id: id)) }
}

private struct SwarmStage: ViewModifier {
    let build: SwarmBuild
    func body(content: Content) -> some View {
        content
            .overlay { SwarmCursors(build: build) }
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { build.screen = geo.size }
                        .onChange(of: geo.size) { _, size in build.screen = size }
                }
                .ignoresSafeArea()
            }
            .environment(build)
            .onAppear { build.arm() }
    }
}

private struct SwarmMaybe: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.swarm(id) } else { content }
    }
}

private enum SwarmInk {
    static let select = Color(red: 13 / 255, green: 153 / 255, blue: 1)
    static let guide = Color(red: 242 / 255, green: 72 / 255, blue: 34 / 255)
    static let blank = Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255)
    static let ink = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    /// The inspector pill: near-black on light screens, a lifted grey on dark ones.
    static let pill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 72 / 255, green: 72 / 255, blue: 76 / 255, alpha: 1)
        : UIColor(red: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1) })
}

private struct SwarmPiece: ViewModifier {
    let id: String
    @Environment(SwarmBuild.self) private var build: SwarmBuild?

    private struct Look {
        var opacity = 1.0
        /// Share of the width shown, from the leading edge.
        var reveal: CGFloat = 1
        var scale: CGFloat = 1
        var anchor: UnitPoint = .center
        var offset: CGFloat = 0
        var offsetY: CGFloat = 0
        /// Progress to hand the marks, when there are any to draw.
        var marks: Double?
        var move: SwarmBuild.Move = .fade
        var shift: CGSize = .zero
    }

    func body(content: Content) -> some View {
        let look = look
        content
            .mask {
                // a wipe from the leading edge while typing or penning; otherwise
                // wide open, with room for shadows
                GeometryReader { geo in
                    let open = look.reveal >= 1
                    Rectangle()
                        .frame(width: open ? geo.size.width + 160 : geo.size.width * look.reveal + 4,
                               height: geo.size.height + 160)
                        .offset(x: open ? -80 : -4, y: -80)
                }
            }
            .opacity(look.opacity)
            .overlay {
                if let p = look.marks {
                    GeometryReader { geo in
                        SwarmMarks(move: look.move, p: p, size: geo.size,
                                   above: build?.pillAbove(build?.frames[id] ?? .zero) ?? false, shift: look.shift)
                    }
                }
            }
            .scaleEffect(look.scale, anchor: look.anchor)
            .offset(x: look.offset, y: look.offsetY)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { build?.frames[id] = $0 }
    }

    private var look: Look {
        guard let build, let step = build.step(id) else { return Look() }
        var look = Look()
        if build.phase == .done {
            // the finished screen: erased pieces stay erased
            if case .erase = step.move { look.opacity = 0 }
            return look
        }
        look.move = step.move
        // before the build begins everything waits unseen, except what an edit will later change
        let p = build.phase == .pending ? -1 : (build.time - step.start) / step.length
        if p >= 0, p < 1 { look.marks = p }
        switch step.move {
        case .draw:
            look.opacity = p < 0.5 ? 0 : SwarmCurve.inOut((p - 0.5) / 0.4)
        case .type(let grow):
            look.opacity = p < 0 ? 0 : 1
            if p < 1 {
                look.reveal = Self.typed(p / (grow ? SwarmCurve.typingShare : 1))
                if grow {
                    look.scale = SwarmCurve.grow(p)
                    look.anchor = .bottomLeading
                }
            }
        case .pen:
            look.opacity = p < 0 ? 0 : 1
            if p < 1 { look.reveal = CGFloat(max(0, p)) }
        case .pop:
            look.opacity = p < 0 ? 0 : min(1, p * 5)
            look.scale = p < 0 ? 0.01 : p < 1 ? CGFloat(SwarmCurve.back(p)) : 1
        case .duplicate(let dx):
            look.opacity = p < 0 ? 0 : 1
            if p < 0.5 { look.offset = dx * CGFloat(1 - SwarmCurve.inOut(max(0, p) / 0.5)) }
        case .duplicateDown(let dy):
            look.opacity = p < 0 ? 0 : 1
            if p < 0.5 { look.offsetY = dy * CGFloat(1 - SwarmCurve.inOut(max(0, p) / 0.5)) }
        case .edit:
            if p >= 0.45, p < 1 { look.reveal = Self.typed((p - 0.45) / 0.5) }
        case .fade:
            look.opacity = p < 0 ? 0 : SwarmCurve.inOut(p)
            look.marks = nil
        case .guide, .trace, .lift:
            break
        case .erase:
            // there from the start; shrinks away in the second half
            if p >= 1 {
                look.opacity = 0
            } else if p >= 0.55 {
                let k = SwarmCurve.inOut((p - 0.55) / 0.4)
                look.opacity = 1 - k
                look.scale = 1 - 0.18 * CGFloat(k)
            }
        case .move:
            let d = build.shift(step), e = CGFloat(SwarmCurve.inOut((p - 0.2) / 0.55))
            look.offset = d.width * (1 - e)
            look.offsetY = d.height * (1 - e)
            look.shift = d
        case .restyle:
            break
        case .comment:
            look.marks = nil
        }
        return look
    }

    /// Typing lands a character at a time, not as a smooth wipe.
    private static func typed(_ x: Double) -> CGFloat {
        let x = max(0, min(1, x))
        return CGFloat((x * 14).rounded(.up) / 14)
    }
}

/// What the tools leave on a piece while it's being worked on: the selection
/// box and its handles, the grey of a fresh rectangle, a caret, a measure.
private struct SwarmMarks: View {
    let move: SwarmBuild.Move
    let p: Double
    let size: CGSize
    /// Put an inspector pill above the piece rather than below it.
    var above = false
    /// For a move: from the new place back to the old one.
    var shift: CGSize = .zero

    var body: some View {
        switch move {
        case .draw(let radius):
            // dragged out corner to corner, then restyled
            let e = CGFloat(SwarmCurve.out(min(1, p / 0.5)))
            let style = CGFloat(SwarmCurve.inOut((p - 0.5) / 0.4))
            let box = CGSize(width: max(1, size.width * e), height: max(1, size.height * e))
            let lift = 1 - SwarmCurve.inOut((p - 0.82) / 0.18)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: min(radius, min(box.width, box.height) / 2) * style, style: .continuous)
                    .fill(SwarmInk.blank)
                    .opacity(Double(1 - style))
                    .frame(width: box.width, height: box.height)
                selection(box)
                    .opacity(lift)
                Text("\(Int(box.width.rounded())) × \(Int(box.height.rounded()))")
                    .font(.system(size: 9.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(RoundedRectangle(cornerRadius: 3).fill(SwarmInk.select))
                    .fixedSize()
                    .frame(width: box.width)
                    .offset(y: box.height + 6)
                    .opacity(p < 0.72 ? 1 : 0)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        case .type(let grow):
            let typing = min(1, p / (grow ? SwarmCurve.typingShare : 1))
            let x = size.width * CGFloat((typing * 14).rounded(.up) / 14)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(SwarmInk.select.opacity(0.75), lineWidth: 1)
                    .padding(-3)
                Rectangle()
                    .fill(SwarmInk.select)
                    .frame(width: 1.5, height: size.height)
                    .offset(x: x + 1)
                    .opacity(typing < 1 || Int(p * 40) % 2 == 0 ? 1 : 0)
            }
        case .pen:
            ZStack(alignment: .leading) {
                node.offset(x: -3)
                node.offset(x: size.width * CGFloat(p) - 3)
            }
            .frame(width: size.width, height: size.height, alignment: .leading)
        case .duplicate(let dx):
            let moving = p < 0.5
            ZStack {
                Rectangle()
                    .strokeBorder(SwarmInk.select, lineWidth: 1)
                    .padding(-3)
                    .opacity(p < 0.9 ? 1 : 0)
                if !moving, p < 0.7 {
                    // selected, about to be retyped
                    Rectangle().fill(SwarmInk.select.opacity(0.26)).padding(-2)
                }
                if moving {
                    // red measure back to the original
                    let gone = abs(dx) * CGFloat(SwarmCurve.inOut(p / 0.5))
                    let span = max(0, gone - size.width - 6)
                    let side: CGFloat = dx < 0 ? -1 : 1
                    Rectangle()
                        .fill(SwarmInk.guide)
                        .frame(width: span, height: 1)
                        .offset(x: side * (size.width / 2 + 3 + span / 2))
                    measure(Int(gone))
                        .offset(x: side * (size.width / 2 + 3 + span / 2), y: -12)
                        .opacity(gone > size.width + 30 ? 1 : 0)
                }
            }
        case .duplicateDown(let dy):
            let moving = p < 0.5
            ZStack {
                Rectangle()
                    .strokeBorder(SwarmInk.select, lineWidth: 1)
                    .padding(-3)
                    .opacity(p < 0.9 ? 1 : 0)
                if !moving, p < 0.7 {
                    Rectangle().fill(SwarmInk.select.opacity(0.12)).padding(-2)
                }
                if moving {
                    // red measure back up to the original
                    let gone = abs(dy) * CGFloat(SwarmCurve.inOut(p / 0.5))
                    let span = max(0, gone - size.height - 6)
                    let side: CGFloat = dy < 0 ? -1 : 1
                    Rectangle()
                        .fill(SwarmInk.guide)
                        .frame(width: 1, height: span)
                        .offset(y: side * (size.height / 2 + 3 + span / 2))
                    measure(Int(gone))
                        .offset(x: 16, y: side * (size.height / 2 + 3 + span / 2))
                        .opacity(gone > size.height + 30 ? 1 : 0)
                }
            }
        case .edit:
            ZStack {
                if p < 0.45 {
                    Rectangle().fill(SwarmInk.select.opacity(0.26)).padding(-2)
                }
                Rectangle()
                    .strokeBorder(SwarmInk.select.opacity(0.75), lineWidth: 1)
                    .padding(-3)
            }
        case .erase:
            // selected, struck through, then gone with the piece
            let strike = CGFloat(SwarmCurve.out((p - 0.2) / 0.25))
            let fade = 1 - SwarmCurve.inOut((p - 0.55) / 0.35)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(SwarmInk.guide.opacity(0.08 * Double(strike)))
                    .padding(-3)
                selection(size)
                Rectangle()
                    .fill(SwarmInk.guide)
                    .frame(width: (size.width + 8) * strike, height: 2)
                    .offset(x: -4, y: size.height / 2 - 1)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .opacity(fade)
        case .move:
            // selected and dragged; a dashed ghost stays where it was
            let dx = shift.width, dy = shift.height
            let e = CGFloat(SwarmCurve.inOut((p - 0.2) / 0.55))
            let gone = hypot(dx, dy) * e
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(SwarmInk.select.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: size.width, height: size.height)
                    .offset(x: dx * e, y: dy * e)
                    .opacity(1 - SwarmCurve.inOut((p - 0.4) / 0.12))   // until the stand-in lets go
                selection(size)
                    .opacity(1 - SwarmCurve.inOut((p - 0.82) / 0.18))
                measure(Int(gone.rounded()))
                    .frame(width: size.width)
                    .offset(y: dy < 0 ? size.height + 7 : -19)
                    .opacity(gone > 12 && p < 0.85 ? 1 : 0)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        case .restyle(let from, let to):
            // selected; the inspector pill shows the old value, then the new
            let shown = SwarmCurve.out((p - 0.12) / 0.18) * (1 - SwarmCurve.inOut((p - 0.86) / 0.14))
            let landed = p >= 0.5
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(SwarmInk.select, lineWidth: 1.5)
                    .padding(-3)
                    .opacity(1 - SwarmCurve.inOut((p - 0.86) / 0.14))
                HStack(spacing: 5) {
                    Text(from)
                        .foregroundStyle(.white.opacity(landed ? 0.45 : 0.95))
                        .strikethrough(landed, color: .white.opacity(0.45))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .opacity(landed ? 1 : 0)
                    Text(to)
                        .foregroundStyle(.white)
                        .opacity(landed ? 1 : 0)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(SwarmInk.pill))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                .fixedSize()
                .scaleEffect(0.85 + 0.15 * shown, anchor: above ? .bottom : .top)
                .opacity(shown)
                .frame(width: size.width)
                .offset(y: above ? -27 : size.height + 8)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        case .pop, .fade, .guide, .trace, .lift, .comment:
            EmptyView()
        }
    }

    private func measure(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(height: 13)
            .background(RoundedRectangle(cornerRadius: 3).fill(SwarmInk.guide))
            .fixedSize()
    }

    /// Selection outline with its four corner handles.
    private func selection(_ box: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(SwarmInk.select, lineWidth: 1.5)
                .frame(width: box.width, height: box.height)
            ForEach(0..<4, id: \.self) { corner in
                node.offset(x: (corner % 2 == 0 ? 0 : box.width) - 3, y: (corner < 2 ? 0 : box.height) - 3)
            }
        }
    }

    private var node: some View {
        Rectangle()
            .fill(.white)
            .frame(width: 6, height: 6)
            .overlay(Rectangle().strokeBorder(SwarmInk.select, lineWidth: 1.2))
    }
}

// MARK: - Cursors and guides

/// The layer above everything: red guides sliding in from the edges and the
/// cursors themselves, one carrying a name.
struct SwarmCursors: View {
    let build: SwarmBuild

    var body: some View {
        if build.phase == .running {
            let time = build.time
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(build.steps.indices, id: \.self) { i in
                        if case .guide(let vertical) = build.steps[i].move, let frame = build.frames[build.steps[i].id] {
                            guide(build.steps[i], vertical: vertical, frame: frame, size: geo.size, time: time)
                        }
                    }
                    ForEach(build.notes.indices, id: \.self) { i in
                        if let frame = build.anchor(build.notes[i].step) {
                            note(build.notes[i], frame: frame, size: geo.size, time: time)
                        }
                    }
                    ForEach(build.cursors.indices, id: \.self) { i in
                        let at = build.position(of: i, in: geo.size)
                        pointer(build.cursors[i])
                            .offset(x: at.x, y: at.y)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A guide rides in with its cursor, holds while things snap to it, and
    /// lets go as the build wraps up.
    private func guide(_ step: SwarmBuild.Step, vertical: Bool, frame: CGRect, size: CGSize, time: Double) -> some View {
        let p = (time - step.start) / step.length
        let e = CGFloat(SwarmCurve.out(p))
        let fade = 1 - SwarmCurve.inOut((time - build.wrap + 0.5) / 0.5)
        return Rectangle()
            .fill(SwarmInk.guide)
            .frame(width: vertical ? 1 : size.width, height: vertical ? size.height : 1)
            .offset(x: vertical ? frame.minX * e : 0, y: vertical ? 0 : frame.minY * e)
            .opacity(p < 0 ? 0 : fade)
    }

    /// A comment: the pin pops in where the cursor clicks, the note opens beside
    /// the piece, folds back into the pin when the next comment starts, and the
    /// pins clear away as the build wraps up.
    @ViewBuilder
    private func note(_ note: SwarmBuild.Note, frame f: CGRect, size: CGSize, time: Double) -> some View {
        let step = note.step
        let who = step.cursor >= 0 && step.cursor < build.cursors.count ? build.cursors[step.cursor] : nil
        let color = who?.color ?? SwarmBuild.Cursor.blue
        let at = SwarmBuild.pinPoint(f, in: size)
        let pop = (time - (step.start + step.length * 0.3)) / 0.3
        let clear = 1 - SwarmCurve.inOut((time - build.wrap) / 0.4)
        let lingers = 1 - SwarmCurve.inOut((time - note.closes - 0.35) / 0.35)
        let open = SwarmCurve.out((time - (step.start + step.length * 0.45)) / 0.3)
            * (1 - SwarmCurve.inOut((time - note.closes) / 0.3))
        let width = min(300, size.width - 32)
        let top = Self.cardOnTop(step, frame: f, size: size)

        if pop > 0 {
            // the note card, in the half of the screen away from the pin
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(color)
                        .frame(width: 20, height: 20)
                        .overlay(Text("\(note.number)").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white))
                    Text(who?.name ?? "Design note")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SwarmInk.ink)
                    Text("now")
                        .font(.system(size: 12))
                        .foregroundStyle(SwarmInk.ink.opacity(0.4))
                }
                Text(note.text)
                    .font(.system(size: 14))
                    .foregroundStyle(SwarmInk.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 5)
            .scaleEffect(0.92 + 0.08 * open, anchor: top ? .top : .bottom)
            .offset(y: CGFloat(1 - open) * (top ? -8 : 8))
            .opacity(open * clear)
            .padding(.top, 64)
            .padding(.bottom, 46)
            .frame(width: size.width, height: size.height, alignment: top ? .top : .bottom)

            // the pin: round, with its point at the spot
            UnevenRoundedRectangle(topLeadingRadius: 13, bottomLeadingRadius: 2, bottomTrailingRadius: 13,
                                   topTrailingRadius: 13, style: .continuous)
                .fill(color)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 13, bottomLeadingRadius: 2, bottomTrailingRadius: 13,
                                                topTrailingRadius: 13, style: .continuous)
                    .strokeBorder(.white, lineWidth: 2))
                .overlay(Text("\(note.number)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1.5)
                .scaleEffect(CGFloat(SwarmCurve.back(pop)), anchor: .bottomLeading)
                .opacity(clear * lingers)
                .offset(x: at.x, y: at.y - 26)
        }
    }

    /// A note card goes in the half of the screen away from its pin, unless told.
    private static func cardOnTop(_ step: SwarmBuild.Step, frame f: CGRect, size: CGSize) -> Bool {
        if case .comment(_, _, let place?) = step.move { return place == .top }
        return f.midY > size.height / 2
    }

    /// Multiplayer arrow: the collaborator's colour, a white edge, an optional name tag.
    private func pointer(_ cursor: SwarmBuild.Cursor) -> some View {
        ZStack(alignment: .topLeading) {
            SwarmArrow()
                .fill(cursor.color)
                .overlay(SwarmArrow().stroke(.white, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round)))
                .frame(width: 13, height: 19)
                .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 1.5)
            if let name = cursor.name {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(cursor.color))
                    .fixedSize()
                    .offset(x: 13, y: 17)
            }
        }
        .frame(width: 0, height: 0, alignment: .topLeading)
    }
}

private struct SwarmArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 12.4, h = rect.height / 18.6
        var p = Path()
        p.move(to: CGPoint(x: 0.6 * w, y: 0.6 * h))
        p.addLine(to: CGPoint(x: 0.6 * w, y: 15.6 * h))
        p.addLine(to: CGPoint(x: 4.5 * w, y: 12.2 * h))
        p.addLine(to: CGPoint(x: 7.2 * w, y: 18 * h))
        p.addLine(to: CGPoint(x: 9.4 * w, y: 17 * h))
        p.addLine(to: CGPoint(x: 6.8 * w, y: 11.3 * h))
        p.addLine(to: CGPoint(x: 11.8 * w, y: 11.3 * h))
        p.closeSubpath()
        return p
    }
}
