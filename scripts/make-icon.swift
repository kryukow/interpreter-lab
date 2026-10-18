import AppKit
import Foundation

// Render a shipping-ready 1024px RGB app icon from the small checked-in
// monochrome source. This avoids large binary images in the repository.
let source = URL(fileURLWithPath: "Design/LabIcon512.png")
let destination = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
guard let logo = NSImage(contentsOf: source),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                    pixelsWide: 1024,
                                    pixelsHigh: 1024,
                                    bitsPerSample: 8,
                                    samplesPerPixel: 3,
                                    hasAlpha: false,
                                    isPlanar: false,
                                    colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0,
                                    bitsPerPixel: 0),
      let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Cannot create app icon bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
graphics.imageInterpolation = .high
logo.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
          from: .zero, operation: .sourceOver, fraction: 1)
graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode app icon PNG")
}
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
try png.write(to: destination)
print("Generated Interpreter Lab 1024x1024 RGB app icon: \(destination.path)")
