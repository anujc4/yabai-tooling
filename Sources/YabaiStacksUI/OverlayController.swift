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

    /// Called with the window id behind a clicked icon. M5 supplies the handler
    /// that asks yabai to focus it.
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

    private func create(_ render: StripRender, height: Double) {
        let panel = StripPanel(
            render: render,
            configuration: configuration,
            icons: icons,
            primaryDisplayHeight: height
        )
        panel.onSelect = { [weak self] id in self?.onSelect?(id) }
        panel.orderFrontRegardless()
        panels[render.key] = panel
    }

    public func removeAll() {
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
        rendered.removeAll()
    }

    public var panelCount: Int { panels.count }
}
