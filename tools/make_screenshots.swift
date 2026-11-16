// Draws the README images in docs/ (light and dark versions) from the app's
// real menu rows (Sources/MenuRows.swift) and icons (Sources/Icons.swift), so
// the pictures always match the app. Not part of the app.
// Run it with: tools/make_screenshots.sh

import AppKit

@main
struct Screenshots {
    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"
        _ = NSApplication.shared
        for dark in [false, true] {
            let name = dark ? "dark" : "light"
            save(menuShot(dark: dark, mode: .cmd), "\(out)/menu-\(name).png")
            save(menuShot(dark: dark, mode: .shift), "\(out)/menu-shift-\(name).png")
            save(modesShot(dark: dark), "\(out)/modes-\(name).png")
            save(menuBarShot(dark: dark), "\(out)/menubar-\(name).png")
        }
    }
}

// MARK: - Helpers

/// Draws into a transparent picture of `size` points (2x pixels), y going down.
func picture(_ size: NSSize, dark: Bool, _ draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                               pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
        draw(size.height)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// A rectangle given from the top (like a web page) in a picture of height `h`.
func box(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ hh: CGFloat, in h: CGFloat) -> NSRect {
    NSRect(x: x, y: h - top - hh, width: w, height: hh)
}

/// A picture of one real view (a menu row), drawn in light or dark mode.
func snapshot(_ view: NSView, dark: Bool) -> NSImage {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    view.appearance = appearance
    let image = NSImage(size: view.bounds.size)
    appearance.performAsCurrentDrawingAppearance {
        view.layoutSubtreeIfNeeded()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                                   pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        image.addRepresentation(rep)
    }
    return image
}

/// A template icon painted in one colour.
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    NSImage(size: image.size, flipped: false) { rect in
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

func text(_ s: String, _ font: NSFont, _ color: NSColor, at p: NSPoint) {
    (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
}

func textWidth(_ s: String, _ font: NSFont) -> CGFloat {
    (s as NSString).size(withAttributes: [.font: font]).width
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// MARK: - The menu, open under the menu bar

func menuShot(dark: Bool, mode: SendShortcut) -> NSBitmapImageRep {
    let rowW = menuRowWidth
    let panelW = rowW + 12
    let W = panelW + 60
    // padding, header, 3 switch rows, separator, Accessibility, Settings, separator, Quit, padding
    let panelH: CGFloat = 270     // 6 + 24 + 3 × 44 + 11 + 28 + 26 + 11 + 26 + 6
    let H: CGFloat = 30 + 8 + panelH + 30

    // The real rows from the app.
    let cmd = SwitchRow(icon: Icons.glyph(.command, bold: true), italic: "⌘ Command + Enter",
                        rest: " to send", subtitle: "Enter adds a new line") { _ in }
    let shift = SwitchRow(icon: Icons.glyph(.shift, bold: true), italic: "⇧ Shift + Enter",
                          rest: " to send", subtitle: "Enter adds a new line · ⌘ + Enter untouched") { _ in }
    let enter = SwitchRow(icon: Icons.enterArrow(), italic: "Enter", rest: " to send",
                          subtitle: "Claude's normal keys") { _ in }
    cmd.isOn = mode == .cmd
    shift.isOn = mode == .shift
    let access = InfoRow(icon: Icons.symbol("accessibility"), label: "Accessibility")
    access.iconView.contentTintColor = .systemGreen
    access.statusField.stringValue = "Granted"
    let rows = [cmd, shift, enter].map { snapshot($0, dark: dark) }
    let accessImage = snapshot(access, dark: dark)

    return picture(NSSize(width: W, height: H), dark: dark) { h in
        let label = NSColor.labelColor, secondary = NSColor.secondaryLabelColor
        // Menu bar strip.
        let bar = box(0, 0, W, 30, in: h)
        (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.91, alpha: 1)).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10).fill()
        bar.insetBy(dx: 0, dy: 0).divided(atDistance: 10, from: .minYEdge).slice.fill()
        let barFont = NSFont.systemFont(ofSize: 13)
        text("Claude", .boldSystemFont(ofSize: 13), label, at: NSPoint(x: 16, y: h - 22))
        var x: CGFloat = 16 + textWidth("Claude", .boldSystemFont(ofSize: 13)) + 18
        for item in ["File", "Edit", "View"] {
            text(item, barFont, label, at: NSPoint(x: x, y: h - 22)); x += textWidth(item, barFont) + 18
        }
        let clock = "Mon 10:30"
        text(clock, barFont, label, at: NSPoint(x: W - 16 - textWidth(clock, barFont), y: h - 22))
        let pill = box(W - 16 - textWidth(clock, barFont) - 16 - 36, 3, 36, 24, in: h)
        (dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.10)).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        tinted(Icons.glyph(.star, size: 22), label)
            .draw(in: NSRect(x: pill.midX - 11, y: pill.midY - 11, width: 22, height: 22))

        // Menu panel with shadow.
        let panel = box(W - 30 - panelW, 38, panelW, panelH, in: h)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.22)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.965, alpha: 1)).setFill()
        let shape = NSBezierPath(roundedRect: panel, xRadius: 11, yRadius: 11)
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.12)).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()

        // Contents, top to bottom.
        let left = panel.minX + 6
        var top = 38 + 6.0
        text("Send key", .systemFont(ofSize: 11.5, weight: .semibold), secondary,
             at: NSPoint(x: left + 14, y: h - top - 18))
        top += 24
        for row in rows {
            row.draw(in: box(left, top, rowW, 44, in: h)); top += 44
        }
        func separator() {
            secondary.withAlphaComponent(0.25).setFill()
            box(left + 14, top + 5, rowW - 28, 1, in: h).fill(); top += 11
        }
        separator()
        accessImage.draw(in: box(left, top, rowW, 28, in: h)); top += 28
        func item(_ symbol: String, _ title: String, _ key: String?) {
            if let icon = Icons.symbol(symbol) {
                let s = icon.size
                tinted(icon, label).draw(in: box(left + 14 + (18 - s.width) / 2, top + (26 - s.height) / 2,
                                                 s.width, s.height, in: h))
            }
            text(title, .menuFont(ofSize: 13), label, at: NSPoint(x: left + 41, y: h - top - 20))
            if let key = key {
                let f = NSFont.menuFont(ofSize: 13)
                text(key, f, secondary, at: NSPoint(x: left + rowW - 14 - textWidth(key, f), y: h - top - 20))
            }
            top += 26
        }
        item("gearshape", "Open Accessibility Settings…", nil)
        separator()
        item("power", "Quit SendKey for Claude", "⌘Q")
    }
}

// MARK: - What the keys do in each mode

func modesShot(dark: Bool) -> NSBitmapImageRep {
    let cardW: CGFloat = 380, cardH: CGFloat = 214, gap: CGFloat = 20
    let W = cardW * 2 + gap + 8, H = cardH + 8
    return picture(NSSize(width: W, height: H), dark: dark) { h in
        let label = NSColor.labelColor, secondary = NSColor.secondaryLabelColor
        let cards: [(String, String?, [(keys: [String], result: String, send: Bool)])] = [
            ("⌘ Command + Enter mode", "default", [
                (["↩"], "New line", false),
                (["⌘", "↩"], "Send", true),
                (["⇧", "↩"], "New line", false)]),
            ("⇧ Shift + Enter mode", nil, [
                (["↩"], "New line", false),
                (["⌘", "↩"], "Claude's own ⌘ + Enter", false),
                (["⇧", "↩"], "Send", true)]),
        ]
        for (i, card) in cards.enumerated() {
            let cx = 4 + CGFloat(i) * (cardW + gap)
            let frame = box(cx, 4, cardW, cardH, in: h)
            let shape = NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14)
            (dark ? NSColor(white: 0.14, alpha: 1) : NSColor.white).setFill()
            shape.fill()
            (dark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.12)).setStroke()
            shape.lineWidth = 1
            shape.stroke()

            let titleFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
            text(card.0, titleFont, label, at: NSPoint(x: cx + 22, y: h - 4 - 40))
            if let tag = card.1 {
                let f = NSFont.systemFont(ofSize: 11, weight: .semibold)
                let tx = cx + 22 + textWidth(card.0, titleFont) + 10
                let tagBox = box(tx, 4 + 21, textWidth(tag, f) + 16, 20, in: h)
                NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: tagBox, xRadius: 10, yRadius: 10).fill()
                text(tag, f, .controlAccentColor, at: NSPoint(x: tagBox.minX + 8, y: tagBox.minY + 3))
            }

            for (r, row) in card.2.enumerated() {
                let top = 4 + 62 + CGFloat(r) * 48
                var x = cx + 22
                for (k, key) in row.keys.enumerated() {
                    if k > 0 {
                        text("+", .systemFont(ofSize: 15), secondary, at: NSPoint(x: x + 2, y: h - top - 26))
                        x += 18
                    }
                    let kw: CGFloat = key == "↩" ? 52 : 36
                    let cap = box(x, top + 2, kw, 34, in: h)
                    let capShape = NSBezierPath(roundedRect: cap, xRadius: 7, yRadius: 7)
                    (dark ? NSColor(white: 0.26, alpha: 1) : NSColor(white: 0.975, alpha: 1)).setFill()
                    capShape.fill()
                    (dark ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 0, alpha: 0.22)).setStroke()
                    capShape.lineWidth = 1
                    capShape.stroke()
                    let f = NSFont.systemFont(ofSize: 17, weight: .medium)
                    text(key, f, label, at: NSPoint(x: cap.midX - textWidth(key, f) / 2, y: cap.minY + 6))
                    x += kw
                }
                text("→", .systemFont(ofSize: 17), secondary, at: NSPoint(x: cx + 160, y: h - top - 28))
                let rf = NSFont.systemFont(ofSize: 15, weight: row.send ? .semibold : .regular)
                let rx = cx + 196
                if row.send {
                    let pill = box(rx - 2, top + 6, textWidth(row.result, rf) + 24, 26, in: h)
                    NSColor.controlAccentColor.setFill()
                    NSBezierPath(roundedRect: pill, xRadius: 13, yRadius: 13).fill()
                    text(row.result, rf, .white, at: NSPoint(x: pill.minX + 12, y: pill.minY + 4))
                } else {
                    text(row.result, rf, row.keys.first == "⌘" ? secondary : label,
                         at: NSPoint(x: rx, y: h - top - 27))
                }
            }
        }
    }
}

// MARK: - The menu bar icon in its three states

func menuBarShot(dark: Bool) -> NSBitmapImageRep {
    let W: CGFloat = 640, H: CGFloat = 56
    return picture(NSSize(width: W, height: H), dark: dark) { h in
        let label = NSColor.labelColor
        let bar = box(4, 4, W - 8, 48, in: h)
        (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 12, yRadius: 12).fill()
        let states: [(String, Bool, Bool)] = [("Swap on", false, false),
                                              ("Enter to send", true, false),
                                              ("Permission missing", false, true)]
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        for (i, s) in states.enumerated() {
            let x = 24 + CGFloat(i) * 205
            let icon = tinted(Icons.glyph(.star, warning: s.2, size: 22), label)
            icon.draw(in: box(x, 17, 22, 22, in: h), from: .zero, operation: .sourceOver,
                      fraction: s.1 ? 0.38 : 1)
            text(s.0, font, label, at: NSPoint(x: x + 32, y: h - 37))
        }
    }
}
