import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconsetDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.55, blue: 0.25, alpha: 1.0),
        NSColor(calibratedRed: 0.02, green: 0.30, blue: 0.15, alpha: 1.0)
    ])
    gradient?.draw(in: path, angle: -90)

    let symbolSize = size * 0.5
    if let symbol = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        let symRect = NSRect(
            x: (size - symbolSize) / 2,
            y: (size - symbolSize) / 2 - size * 0.02,
            width: symbolSize,
            height: symbolSize
        )
        NSColor.white.set()
        configured.isTemplate = true
        configured.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

for size in sizes {
    for scale in [1, 2] {
        let pixelSize = CGFloat(size * scale)
        let image = makeIcon(size: pixelSize)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { continue }
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(size)x\(size)\(suffix).png"
        let url = URL(fileURLWithPath: iconsetDir).appendingPathComponent(name)
        try? png.write(to: url)
    }
}
