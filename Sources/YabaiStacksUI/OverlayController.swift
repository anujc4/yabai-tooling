import AppKit
import YabaiStacksCore

/// Owns the live panels and applies a `StripDiff`. Panels are reused across refreshes.
@MainActor
public final class OverlayController {
    private let configuration: Configuration
    private let icons: AppIconProvider
    private var panels: [StackKey: StripPanel] = [:]
    private var rendered: [StackKey: StripRender] = [:]

    /// Two independent reasons to be out of the way, kept apart because either can end
    /// while the other holds. Mission Control takes every strip, hover only some.
    private var parkedByMissionControl = false
    private var parkedByHover: Set<StackKey> = []
    private var hoverMonitor: Any?

    /// Never called under `--hide-on-hover`, where no click action is registered.
    public var onSelect: ((Int) -> Void)?

    public init(configuration: Configuration, scale: Double = Double(NSScreen.main?.backingScaleFactor ?? 2)) {
        self.configuration = configuration
        icons = AppIconProvider(pointSize: configuration.iconSize, scale: scale)
    }

    /// The primary display is `NSScreen.screens[0]`, not `.main`, which follows the key window.
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
        // The home rects have moved, so the hover set can change though the cursor has not.
        if refreshHoverState() { applyParking(animated: false) }

        let height = primaryDisplayHeight

        for update in diff.updated {
            guard let panel = panels.removeValue(forKey: update.previousKey) else {
                create(update.render, height: height)
                continue
            }
            // Placed, not framed at its home rect: a refresh coalesced in behind a
            // hide would otherwise drag the panel back on screen.
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

    /// A floating panel left on top of Mission Control looks pinned to the glass.
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

    private static func parked(_ home: Rect) -> Rect {
        let screens = NSScreen.screens.map {
            Rect(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.frame.height)
        }
        return StripGeometry.parked(home, beyond: StripGeometry.desktop(of: screens))
    }

    // MARK: - Hover

    /// Mouse movement only: a keyboard monitor is what needs an Accessibility grant.
    /// Installed only while `--hide-on-hover` is set and a strip exists.
    private func updateHoverMonitor() {
        guard configuration.hideOnHover else { return }

        guard !panels.isEmpty else {
            if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
            hoverMonitor = nil
            parkedByHover = []
            return
        }

        guard hoverMonitor == nil else { return }
        // `assumeIsolated` on a queue that turns out not to be main is a crash.
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
