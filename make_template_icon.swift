import AppKit

let args = CommandLine.arguments
guard args.count >= 4,
      let inputImage = NSImage(contentsOfFile: args[1]),
      let size = Int(args[3]) else {
    exit(1)
}
let outputPath = args[2]

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
inputImage.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.bitmapData else { exit(1) }
let bytesPerRow = rep.bytesPerRow
// The source logo has no alpha channel (flat opaque near-white background behind a
// colorful glyph), so derive the silhouette by treating near-white pixels as background.
let whiteThreshold: UInt8 = 235
var mask = [[Bool]](repeating: [Bool](repeating: false, count: size), count: size)
for y in 0..<size {
    for x in 0..<size {
        let offset = y * bytesPerRow + x * 4
        let r = data[offset], g = data[offset + 1], b = data[offset + 2]
        mask[y][x] = !(r > whiteThreshold && g > whiteThreshold && b > whiteThreshold)
    }
}

// Erode the mask a couple of pixels so the glyph's strokes read thinner/more discreet
// in the menu bar, matching the slim weight of other system menu bar icons.
let erosionPasses = 5
for _ in 0..<erosionPasses {
    var eroded = mask
    for y in 0..<size {
        for x in 0..<size {
            guard mask[y][x] else { continue }
            let neighborsForeground = (x > 0 ? mask[y][x - 1] : false)
                && (x < size - 1 ? mask[y][x + 1] : false)
                && (y > 0 ? mask[y - 1][x] : false)
                && (y < size - 1 ? mask[y + 1][x] : false)
            eroded[y][x] = neighborsForeground
        }
    }
    mask = eroded
}

for y in 0..<size {
    for x in 0..<size {
        let offset = y * bytesPerRow + x * 4
        data[offset] = 0
        data[offset + 1] = 0
        data[offset + 2] = 0
        data[offset + 3] = mask[y][x] ? 255 : 0
    }
}

guard let pngData = rep.representation(using: .png, properties: [:]) else { exit(1) }
try pngData.write(to: URL(fileURLWithPath: outputPath))
