import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Generate a valid opaque RGB 1024×1024 iOS icon from the checked-in 512px LAB source.
// NSBitmapImageRep with samplesPerPixel=3 is not reliable on modern CI macOS;
// CoreGraphics uses 4-byte pixels with a skipped alpha byte instead.
let input = URL(fileURLWithPath: "Design/LabIcon512.png")
let output = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let dimension = 1024

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Missing or invalid Design/LabIcon512.png")
}

guard let context = CGContext(
    data: nil,
    width: dimension,
    height: dimension,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Cannot create opaque RGB CoreGraphics context")
}

context.interpolationQuality = .high
let bounds = CGRect(x: 0, y: 0, width: dimension, height: dimension)
context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
context.fill(bounds)
context.draw(sourceImage, in: bounds)

guard let icon = context.makeImage() else {
    fatalError("Failed to render LAB icon")
}

try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL, UTType.png.identifier as CFString, 1, nil
) else {
    fatalError("Cannot create PNG destination")
}
CGImageDestinationAddImage(destination, icon, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write PNG")
}
print("Generated opaque RGB 1024x1024 LAB app icon: \(output.path)")
