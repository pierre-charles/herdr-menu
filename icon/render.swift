import AppKit

// render.swift in.svg out.png width height [in.svg out.png width height ...]: macOS draws SVG itself
let a = Array(CommandLine.arguments.dropFirst())
for i in stride(from: 0, to: a.count, by: 4) {
    guard let image = NSImage(contentsOf: URL(fileURLWithPath: a[i])) else { fatalError("can't read \(a[i])") }
    let w = Int(a[i + 2])!, h = Int(a[i + 3])!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[i + 1]))
}
