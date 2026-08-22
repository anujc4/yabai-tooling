import AppKit

// Overlay rendering arrives in a later milestone; this target exists so the
// AppKit boundary is fixed from the start and stays out of YabaiStacksCore.
public enum YabaiStacksUI {
    @MainActor public static func screenScale() -> CGFloat {
        NSScreen.main?.backingScaleFactor ?? 1
    }
}
