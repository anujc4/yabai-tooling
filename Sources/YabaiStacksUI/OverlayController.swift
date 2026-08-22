import AppKit
import YabaiStacksCore

/// Owns the live panels and applies a `StripDiff` to them. Panels are reused
/// across refreshes — rebuilding them on every yabai event flickers and throws
/// away the icon layers for no reason.
@MainActor
public final class OverlayController {
    private let configuration: Configuration
    private let icons: AppIconProvider
    private var panels: [StackKey: StripPanel] = [:]
    private var rendered: [StackKey: StripRender] = [:]
    private var isHidden = false

    /// Called with the window id behind a clicked icon.
    public var onSelect: ((Int) -> Void)?

    public init(configuration: Configuration, scale: Double = Double(NSScreen.main?.backingScaleFactor ?? 2)) {
        self.configuration = configuration
        icons = AppIconProvider(pointSize: configuration.iconSize, scale: scale)
    }

    /// AppKit's origin sits at the bottom-left of the primary display, which is
    /// `NSScreen.screens[0]` — not `NSScreen.main`, which follows the key window.
    private var primaryDisplayHeight: Double {
        NSScreen.screens.first.map { Double($0.frame.height) } ?? 0
    }

    public func apply(stacks: [Stack], displays: [YabaiDisplay]) {
        let diff = StripReconciler.reconcile(
            previous: rendered,
            stacks: stacks,
            displays: displays,
            configuration: configuration
        )
        apply(diff)
    }

    func apply(_ diff: StripDiff) {
        icons.retain(pids: diff.live.flatMap(\.pids))

        for key in diff.removed {
            panels.removeValue(forKey: key)?.orderOut(nil)
        }

        let height = primaryDisplayHeight

        for update in diff.updated {
            guard let panel = panels.removeValue(forKey: update.previousKey) else {
                create(update.render, height: height)
                continue
            }
            panel.apply(render: update.render, icons: icons, primaryDisplayHeight: height)
            panels[update.key] = panel
        }

        for render in diff.created {
            create(render, height: height)
        }

        rendered = diff.rendered
    }

    static func screenRect(for render: StripRender, primaryDisplayHeight: Double) -> NSRect {
        StripPanel.screenRect(for: render, primaryDisplayHeight: primaryDisplayHeight)
    }

    private func create(_ render: StripRender, height: Double) {
        let panel = StripPanel(
            render: render,
            configuration: configuration,
            icons: icons,
            primaryDisplayHeight: height
        )
        panel.onSelect = { [weak self] id in self?.onSelect?(id) }
        panel.orderFrontRegardless()
        if isHidden {
            panel.slide(to: Self.offScreen(panel.frame), animated: false)
        }
        panels[render.key] = panel
    }

    /// Mission Control draws over everything, and a floating panel sitting on
    /// top of it looks pinned to the glass. Sliding the strips off their own
    /// display edge and back reads as them getting out of the way.
    public func setHidden(_ hidden: Bool, animated: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden

        for (key, panel) in panels {
            guard let render = rendered[key] else { continue }
            let onScreen = Self.screenRect(for: render, primaryDisplayHeight: primaryDisplayHeight)
            let target = hidden ? Self.offScreen(onScreen) : onScreen
            panel.slide(to: target, animated: animated)
        }
    }

    /// Leaves the strip travelling towards the nearest horizontal edge of the
    /// screen it is on, so it exits the way it came in.
    private static func offScreen(_ rect: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.screens.first
        guard let bounds = screen?.frame else { return rect.offsetBy(dx: -rect.width * 2, dy: 0) }
        let exitsLeft = rect.midX < bounds.midX
        let dx = exitsLeft ? bounds.minX - rect.maxX - 8 : bounds.maxX - rect.minX + 8
        return rect.offsetBy(dx: dx, dy: 0)
    }

    public func removeAll() {
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
        rendered.removeAll()
    }

    public var panelCount: Int { panels.count }
}
