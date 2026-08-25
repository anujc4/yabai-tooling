import AppKit
import YabaiStacksCore

@MainActor
public final class AppIconProvider {
    public static let defaultCapacity = 64

    private let cache: KeyedCache<Int, CGImage>

    public init(pointSize: Double, scale: Double, capacity: Int = AppIconProvider.defaultCapacity) {
        let pixels = Geometry.devicePixels(pointSize: pointSize, scale: scale)
        cache = KeyedCache(capacity: capacity) { pid in
            Self.rasterise(pid: pid, pixels: pixels)
        }
    }

    /// nil when the app quit between the query and the draw; callers skip that icon.
    public func icon(forPID pid: Int) -> CGImage? {
        cache.value(for: pid)
    }

    public func retain(pids: some Sequence<Int>) {
        cache.retain(pids)
    }

    public func invalidate(pid: Int) {
        cache.invalidate(pid)
    }

    public func invalidateAll() {
        cache.invalidateAll()
    }

    private static func rasterise(pid: Int, pixels: Int) -> CGImage? {
        guard let identifier = pid_t(exactly: pid),
              let application = NSRunningApplication(processIdentifier: identifier),
              let icon = application.icon
        else { return nil }

        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.current = previous }

        icon.draw(
            in: NSRect(x: 0, y: 0, width: Double(pixels), height: Double(pixels)),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        return context.makeImage()
    }
}
