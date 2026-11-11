import AppKit
import SwiftUI

enum AppleScriptRunner {
    private static var compiledScripts: [String: NSAppleScript] = [:]

    @discardableResult
    static func run(_ source: String, isReusable: Bool = true) -> NSAppleEventDescriptor? {
        guard let script = compiledScripts[source] ?? NSAppleScript(source: source) else { return nil }
        if isReusable {
            compiledScripts[source] = script
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        return errorInfo == nil ? result : nil
    }
}

extension NSImage {
    var accentColor: Color? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 4,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        draw(in: NSRect(x: 0, y: 0, width: 1, height: 1), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let averageColor = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        averageColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let vividSaturation = min(max(saturation * 1.4, 0.3), 0.9)
        let vividBrightness = max(brightness, 0.85)
        return Color(hue: Double(hue), saturation: Double(vividSaturation), brightness: Double(vividBrightness))
    }
}
