import CoreText
import SwiftUI
import UIKit

struct HomeGreetingAnchor {
    let bounds: Anchor<CGRect>
    let title: String
}

private struct LoginConfirmationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var loginConfirmationActive: Bool {
        get { self[LoginConfirmationKey.self] }
        set { self[LoginConfirmationKey.self] = newValue }
    }
}

/// Uses the dashboard's measured text frame, including Dynamic Type and wrapping.
struct HomeWelcomeAnimation: View {
    let elapsed: Double
    let destination: CGRect?
    let title: String
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            let move = ease(elapsed, 1.5, 2.29)
            let reveal = ease(elapsed, reduceMotion ? 0 : 1.59, reduceMotion ? 0.2 : 2.29)
            let target = destination ?? CGRect(x: 24, y: geometry.size.height * 0.22, width: geometry.size.width - 48, height: 88)
            let initialScale = min(1.18, (geometry.size.width - 32) / max(1, target.width))
            let scale = 1 + (1 - move) * (initialScale - 1)
            let start = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.48)
            ZStack {
                AuthPalette.background.ignoresSafeArea().opacity(1 - reveal)
                if !reduceMotion {
                    GreetingOutline(title: title, elapsed: elapsed)
                        .frame(width: target.width, height: target.height)
                        .scaleEffect(scale)
                        .position(x: start.x + (target.midX - start.x) * move,
                                  y: start.y + (target.midY - start.y) * move)
                        .opacity(destination == nil ? 1 - reveal : 1)
                    HStack(spacing: 0) {
                        WelcomeMascot(index: 0, elapsed: elapsed)
                        WelcomeMascot(index: 1, elapsed: elapsed)
                    }
                    .frame(width: 232, height: 116)
                    .position(x: geometry.size.width / 2, y: max(70, start.y - target.height / 2 - 78))
                    .opacity(ease(elapsed, 0, 0.25) * (1 - ease(elapsed, 1.29, 1.64)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let p = min(1, max(0, (t - a) / (b - a)))
        return p * p * (3 - 2 * p)
    }
}

private struct GreetingOutline: View {
    let title: String
    let elapsed: Double

    var body: some View {
        Canvas { context, size in
            let font = UIFont.preferredFont(forTextStyle: .largeTitle)
            let bold = UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(.traitBold) ?? font.fontDescriptor, size: font.pointSize)
            let string = NSAttributedString(string: title, attributes: [.font: bold])
            let setter = CTFramesetterCreateWithAttributedString(string)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), nil)
            let lines = CTFrameGetLines(frame) as! [CTLine]
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            for (lineIndex, line) in lines.enumerated() {
                for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    let runFont = attributes[kCTFontAttributeName] as! CTFont
                    let count = CTRunGetGlyphCount(run)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                    for i in 0..<count {
                        guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                        let origin = origins[lineIndex]
                        let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: origin.x + positions[i].x, ty: size.height - origin.y - positions[i].y)
                        let path = Path(glyph).applying(transform)
                        let progress = min(1, max(0, (elapsed - Double(i) * min(0.1, 0.5 / Double(max(1, count)))) / 0.55))
                        context.stroke(path.trimmedPath(from: 0, to: progress), with: .color(SetuColor.textPrimary), lineWidth: 0.65)
                        context.fill(path, with: .color(SetuColor.textPrimary.opacity(min(1, max(0, (progress - 0.6) / 0.4)))))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The approved lightweight mesh motion, using one consistent pose per character.
private struct WelcomeMascot: View {
    let index: Int
    let elapsed: Double

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 288, y: size.height / 288)
            let image = context.resolve(Image(index == 0 ? "WelcomeXueliang" : "WelcomeRinna"))
            let t = max(0, elapsed - Double(index) * 0.12)
            let wave = sin(t * 13) * sin(min(1, t / 1.25) * .pi)
            func vertex(_ p: CGPoint) -> CGPoint {
                let pointX = Double(p.x)
                let pointY = Double(p.y)
                let hx: Double = index == 0 ? 195 : 68
                let hy: Double = index == 0 ? 100 : 112
                let weight = exp(-((pointX - hx) * (pointX - hx) / 700.0 + (pointY - hy) * (pointY - hy) / 750.0))
                let angle = 0.28 * wave * weight
                let px: Double = index == 0 ? 178 : 85
                let dx = pointX - px
                let dy = pointY - 145.0
                let sway = (index == 0 ? 4.0 : -4.0) * sin(t * 3) * max(0.0, 1 - pointY / 250.0)
                return CGPoint(x: px + dx * cos(angle) - dy * sin(angle) + sway + 16.0,
                               y: 145.0 + dx * sin(angle) + dy * cos(angle) - 2.4 * sin(t * 5) * max(0.0, 1 - pointY / 256.0) + 16.0)
            }
            func triangle(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) {
                let a = vertex(p), b = vertex(q), c = vertex(r)
                let det = (q.x-p.x)*(r.y-p.y)-(r.x-p.x)*(q.y-p.y)
                let aa = ((b.x-a.x)*(r.y-p.y)-(c.x-a.x)*(q.y-p.y))/det
                let bb = ((b.y-a.y)*(r.y-p.y)-(c.y-a.y)*(q.y-p.y))/det
                let cc = ((c.x-a.x)*(q.x-p.x)-(b.x-a.x)*(r.x-p.x))/det
                let dd = ((c.y-a.y)*(q.x-p.x)-(b.y-a.y)*(r.x-p.x))/det
                var layer = context
                var clip = Path()
                let center = CGPoint(x: (a.x+b.x+c.x)/3, y: (a.y+b.y+c.y)/3)
                for (i, v) in [a,b,c].enumerated() {
                    let expanded = CGPoint(x: v.x+(v.x-center.x)*0.015, y: v.y+(v.y-center.y)*0.015)
                    if i == 0 { clip.move(to: expanded) } else { clip.addLine(to: expanded) }
                }
                clip.closeSubpath()
                layer.clip(to: clip)
                layer.concatenate(CGAffineTransform(a: aa, b: bb, c: cc, d: dd, tx: a.x-aa*p.x-cc*p.y, ty: a.y-bb*p.x-dd*p.y))
                layer.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
            }
            for y in stride(from: 0, to: 256, by: 16) {
                for x in stride(from: 0, to: 256, by: 16) {
                    let a = CGPoint(x: x, y: y), b = CGPoint(x: x+16, y: y), c = CGPoint(x: x, y: y+16), d = CGPoint(x: x+16, y: y+16)
                    triangle(a,b,c); triangle(b,d,c)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
