import AppKit

// MARK: - Иконка в строке меню: остров с четырёхлучевой звездой
// Рисуется кодом как «шаблон» — macOS сама красит её в цвет строки меню
// (чёрная на светлой, белая на тёмной)

enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            // Остров — закруглённая капсула
            let pill = NSBezierPath(roundedRect: NSRect(x: 1, y: 3.5, width: 20, height: 9),
                                    xRadius: 4.5, yRadius: 4.5)
            NSColor.black.setFill()
            pill.fill()

            // Звезда «вырезается» из капсулы
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            star(center: NSPoint(x: 11, y: 8), outer: 3.6, inner: 0.9).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "RequiemNotch"
        return image
    }()

    /// Четырёхлучевая звезда
    private static func star(center: NSPoint, outer: CGFloat, inner: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for i in 0..<8 {
            let radius = i % 2 == 0 ? outer : inner
            let angle = CGFloat(i) * .pi / 4 + .pi / 2
            let point = NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }
}
