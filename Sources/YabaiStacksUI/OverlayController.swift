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

    /// Two independent reasons to be out of the way, kept apart because either
    /// can end while the other still holds: a cursor leaving a strip must not
    /// bring it back on top of Mission Control. Mission Control takes every
    /// strip; hover takes only the ones actually under the cursor.
    private var parkedByMissionControl = false
    private var parkedByHover: Set<StackKey> = []
    private var hoverMonitor: Any?

    /// Called with the window id behind a clicked icon. Never called under
    /// `--hide-on-hover`, where no click action is registered at all.
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

        rendered = diff.rendered
        // The home rects have just moved, so which strips the cursor is over can
        // have changed even though the cursor has not. Decided before anything
        // is placed, so each panel is put in its final position once.
        if refreshHoverState() { applyParking(animated: false) }

        let height = primaryDisplayHeight

        for update in diff.updated {
            guard let panel = panels.removeValue(forKey: update.previousKey) else {
                create(update.render, height: height)
                continue
            }
            // Placed rather than framed at its home rect: a refresh coalesced in
            // behind a hide would otherwise drag every panel it touches back on
            // screen and undo it.
            panel.apply(
                render: update.render,
                icons: icons,
                screenFrame: placement(for: update.render, height: height)
            )
            panels[update.key] = panel
        }

        for render in diff.created {
            create(render, height: height)
        }

        updateHoverMonitor()
    }

    private func create(_ render: StripRender, height: Double) {
        let panel = StripPanel(
            render: render,
            configuration: configuration,
            icons: icons,
            primaryDisplayHeight: height
        )
        if !configuration.hideOnHover {
            panel.onSelect = { [weak self] id in self?.onSelect?(id) }
        }
        panel.orderFrontRegardless()
        panel.slide(to: placement(for: render, height: height), animated: false)
        panels[render.key] = panel
    }

    /// Mission Control draws over everything, and a floating panel sitting on
    /// top of it looks pinned to the glass. Sliding the strips off the desktop's
    /// edge and back reads as them getting out of the way.
    public func setHidden(_ hidden: Bool, animated: Bool) {
        guard hidden != parkedByMissionControl else { return }
        parkedByMissionControl = hidden
        applyParking(animated: animated)
    }

    private func isParked(_ key: StackKey) -> Bool {
        parkedByMissionControl || parkedByHover.contains(key)
    }

    private func applyParking(animated: Bool) {
        let height = primaryDisplayHeight
        for (key, panel) in panels {
            guard let render = rendered[key] else { continue }
            panel.slide(to: placement(for: render, height: height), animated: animated)
        }
    }

    private func placement(for render: StripRender, height: Double) -> NSRect {
        let home = Self.homeRect(for: render, primaryDisplayHeight: height)
        return Self.nsRect(isParked(render.key) ? Self.parked(home) : home)
    }

    static func homeRect(for render: StripRender, primaryDisplayHeight: Double) -> Rect {
        Geometry.appKitRect(fromYabai: render.layout.frame, primaryDisplayHeight: primaryDisplayHeight)
    }

    static func nsRect(_ rect: Rect) -> NSRect {
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    /// Measured against every screen at once. Sending a strip past the near edge
    /// of its own screen leaves it fully visible on the neighbouring one, where
    /// Mission Control is drawing too.
    private static func parked(_ home: Rect) -> Rect {
        let screens = NSScreen.screens.map {
            Rect(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.frame.height)
        }
        return StripGeometry.parked(home, beyond: StripGeometry.desktop(of: screens))
    }

    // MARK: - Hover

    /// Only armed while `--hide-on-hover` is set and there is something to
    /// hover over, so the common case installs no monitor at all. The monitor is
    /// for mouse movement only — a keyboard monitor is what needs an
    /// Accessibility grant — and it does no work while the cursor is still.
    private func updateHoverMonitor() {
        guard configuration.hideOnHover else { return }

        guard !panels.isEmpty else {
            if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
            hoverMonitor = nil
            parkedByHover = []
            return
        }

        guard hoverMonitor == nil else { return }
        // The hop to main is explicit rather than assumed: `assumeIsolated` on a
        // queue that turned out not to be main is a crash, and this monitor's
        // delivery queue is not something the daemon gets to check.
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.refreshHoverState() else { return }
                    self.applyParking(animated: true)
                }
            }
        }
    }

    @discardableResult
    private func refreshHoverState() -> Bool {
        guard configuration.hideOnHover else { return false }
        let height = primaryDisplayHeight
        let location = NSEvent.mouseLocation
        let hidden = HoverGate.hidden(
            cursor: Point(x: Double(location.x), y: Double(location.y)),
            homes: rendered.mapValues { Self.homeRect(for: $0, primaryDisplayHeight: height) },
            previouslyHidden: parkedByHover
        )
        guard hidden != parkedByHover else { return false }
        parkedByHover = hidden
        return true
    }

    public func removeAll() {
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
        rendered.removeAll()
        updateHoverMonitor()
    }

    public var panelCount: Int { panels.count }
}
