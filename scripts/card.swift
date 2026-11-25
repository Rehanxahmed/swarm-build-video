// Draws the text layers for a Before → After film, as transparent PNGs the
// size of the mockup (render.py calls this; ffmpeg here has no text filter).
//
//     swift card.swift spec.json outdir
//
// spec.json: {"W": 1440, "H": 1800, "chipY": 1726,
//             "phones": [[x, y, w, h], [x, y, w, h]],     // where the end card's phones sit
//             "title": "What changed",                    // optional
//             "decisions": [{"title": "...", "why": "..."}]}
//
// Writes outdir/chip-before.png, outdir/chip-after.png and outdir/card-text.png.

import AppKit

struct Decision: Decodable { var title: String; var why: String? }
struct Spec: Decodable {
    var W: CGFloat
    var H: CGFloat
    var chipY: CGFloat
    var phones: [[CGFloat]]
    var title: String?
    var decisions: [Decision]?
}

let args = CommandLine.arguments
guard args.count == 3, let data = FileManager.default.contents(atPath: args[1]),
      let spec = try? JSONDecoder().decode(Spec.self, from: data) else {
    FileHandle.standardError.write("usage: swift card.swift spec.json outdir\n".data(using: .utf8)!)
    exit(2)
}
let outdir = URL(fileURLWithPath: args[2])

let ink = NSColor(srgbRed: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1)
let grey = NSColor(srgbRed: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 0.5)
let blue = NSColor(srgbRed: 13 / 255, green: 153 / 255, blue: 1, alpha: 1)
let green = NSColor(srgbRed: 20 / 255, green: 174 / 255, blue: 92 / 255, alpha: 1)
let stone = NSColor(srgbRed: 160 / 255, green: 160 / 255, blue: 166 / 255, alpha: 1)

/// Draws into a transparent canvas with a top-left origin and saves it as PNG.
func canvas(_ name: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(spec.W), pixelsHigh: Int(spec.H),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    ctx.cgContext.translateBy(x: 0, y: spec.H)
    ctx.cgContext.scaleBy(x: 1, y: -1)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: outdir.appendingPathComponent(name))
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                               .foregroundColor: color, .kern: kern])
}

/// A pill label: a coloured dot and a word, centred on (cx, cy).
func chip(_ word: String, dot: NSColor, cx: CGFloat, cy: CGFloat) {
    let label = text(word, size: 30, weight: .semibold, color: ink, kern: 0.2)
    let size = label.size()
    let w = size.width + 36 + 18 + 14, h: CGFloat = 60
    let box = NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -4)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: box, xRadius: h / 2, yRadius: h / 2).fill()
    NSGraphicsContext.restoreGraphicsState()
    dot.setFill()
    NSBezierPath(ovalIn: NSRect(x: box.minX + 24, y: cy - 7, width: 14, height: 14)).fill()
    label.draw(at: NSPoint(x: box.minX + 24 + 14 + 14, y: cy - size.height / 2))
}

canvas("chip-before.png") { chip("Before", dot: stone, cx: spec.W / 2, cy: spec.chipY) }
canvas("chip-after.png") { chip("After", dot: green, cx: spec.W / 2, cy: spec.chipY) }

canvas("card-text.png") {
    // labels over the two phones, and an arrow between them
    let left = spec.phones[0], right = spec.phones[1]
    chip("Before", dot: stone, cx: left[0] + left[2] / 2, cy: left[1] - 52)
    chip("After", dot: green, cx: right[0] + right[2] / 2, cy: right[1] - 52)
    let mid = NSPoint(x: (left[0] + left[2] + right[0]) / 2, y: left[1] + left[3] / 2)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: mid.x - 34, y: mid.y - 34, width: 68, height: 68)).fill()
    let arrow = NSBezierPath()
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: mid.x - 13, y: mid.y)); arrow.line(to: NSPoint(x: mid.x + 13, y: mid.y))
    arrow.move(to: NSPoint(x: mid.x + 3, y: mid.y - 10)); arrow.line(to: NSPoint(x: mid.x + 13, y: mid.y))
    arrow.line(to: NSPoint(x: mid.x + 3, y: mid.y + 10))
    ink.setStroke()
    arrow.stroke()

    // the decisions, numbered like the comment pins
    let items = Array((spec.decisions ?? []).prefix(4))
    guard !items.isEmpty else { return }
    let x0 = left[0], width = right[0] + right[2] - left[0]
    var y = left[1] + left[3] + 70
    let heading = text((spec.title ?? "What changed").uppercased(), size: 24, weight: .semibold, color: grey, kern: 2)
    heading.draw(at: NSPoint(x: x0, y: y))
    y += 58
    let room = spec.H - 50 - y
    let pitch = min(118, room / CGFloat(items.count))
    for (i, d) in items.enumerated() {
        blue.setFill()
        let r = NSRect(x: x0, y: y + 2, width: 44, height: 44)
        NSBezierPath(ovalIn: r).fill()
        let n = text("\(i + 1)", size: 22, weight: .bold, color: .white)
        n.draw(at: NSPoint(x: r.midX - n.size().width / 2, y: r.midY - n.size().height / 2))
        let title = text(d.title, size: 34, weight: .semibold, color: ink)
        title.draw(with: NSRect(x: x0 + 66, y: y, width: width - 66, height: 44),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        if let why = d.why, pitch > 80 {
            text(why, size: 25, weight: .regular, color: grey)
                .draw(with: NSRect(x: x0 + 66, y: y + 46, width: width - 66, height: 34),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        y += pitch
    }
}
