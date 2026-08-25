import AppKit
import YabaiStacksCore

extension RGBAColor {
    var cgColor: CGColor {
        CGColor(red: redFraction, green: greenFraction, blue: blueFraction, alpha: alphaFraction)
    }
}

/// Draws one strip. Icons are `CALayer` contents, so a refresh that only changes
/// the highlight composites rather than redraws.
final class StripView: NSView {
    private let configuration: Configuration
    private let background = CALayer()
    private var iconLayers: [CALayer] = []
    private var highlight = CALayer()

    private(set) var render: StripRender

    var onSelect: ((Int) -> Void)?

    init(render: StripRender, configuration: Configuration, icons: AppIconProvider) {
        self.render = render
        self.configuration = configuration
        super.init(frame: NSRect(origin: .zero, size: NSSize(
            width: render.layout.frame.width,
            height: render.layout.frame.height
        )))

        wantsLayer = true
        layer?.addSublayer(background)
        layer?.addSublayer(highlight)
        apply(render: render, icons: icons)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Icon rects are computed in yabai's top-left-origin space, so the view shares it;
    /// unflipped, a vertical strip would render its first member at the bottom.
    override var isFlipped: Bool { true }

    func apply(render: StripRender, icons: AppIconProvider) {
        self.render = render

        // The panel is resized to match before this runs, so bounds are current.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        background.frame = bounds
        background.backgroundColor = configuration.backgroundColor.cgColor
        background.cornerRadius = configuration.cornerRadius

        layoutIcons(render: render, icons: icons)
        layoutHighlight(render: render)
    }

    private func layoutIcons(render: StripRender, icons: AppIconProvider) {
        let wanted = render.count
        while iconLayers.count < wanted {
            let layer = CALayer()
            layer.contentsGravity = .resizeAspect
            self.layer?.addSublayer(layer)
            iconLayers.append(layer)
        }
        for surplus in iconLayers[wanted...] { surplus.removeFromSuperlayer() }
        iconLayers.removeLast(iconLayers.count - wanted)

        for (index, layer) in iconLayers.enumerated() {
            layer.frame = localRect(at: index, in: render)
            layer.contents = render.pid(forIcon: index).flatMap { icons.icon(forPID: $0) }
            layer.opacity = index == render.layout.activeIndex ? 1 : Float(configuration.inactiveOpacity)
            // A pid whose app quit mid-refresh has no icon; the slot stays blank.
            layer.isHidden = layer.contents == nil
        }
    }

    /// Ringed rather than tinted, so the icon itself stays recognisable.
    private func layoutHighlight(render: StripRender) {
        guard let active = render.layout.activeIndex else {
            highlight.isHidden = true
            return
        }
        let inset = max(1, configuration.borderWidth)
        let frame = localRect(at: active, in: render).insetBy(dx: -inset, dy: -inset)
        highlight.isHidden = false
        highlight.frame = frame
        highlight.borderColor = configuration.activeColor.cgColor
        highlight.borderWidth = inset
        // Half the shorter side is already a full capsule; past that renders the same.
        highlight.cornerRadius = min(configuration.cornerRadius, min(frame.width, frame.height) / 2)
        highlight.backgroundColor = .clear
    }

    private func localRect(at index: Int, in render: StripRender) -> CGRect {
        guard let rect = render.layout.iconRect(at: index) else { return .zero }
        let frame = render.layout.frame
        return CGRect(
            x: rect.minX - frame.minX,
            y: rect.minY - frame.minY,
            width: rect.width,
            height: rect.height
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let id = render.layout.windowID(atLocal: Point(x: point.x, y: point.y)) else { return }
        onSelect?(id)
    }
}

/// A borderless, non-activating panel sized exactly to its strip. Sizing it to the
/// strip is what lets it take clicks without an event tap or an Accessibility grant.
final class StripPanel: NSPanel {
    private let stripView: StripView

    init(render: StripRender, configuration: Configuration, icons: AppIconProvider, primaryDisplayHeight: Double) {
        stripView = StripView(render: render, configuration: configuration, icons: icons)

        super.init(
            contentRect: Self.screenRect(for: render, primaryDisplayHeight: primaryDisplayHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        // Out of the mouse path entirely, so a click cannot be swallowed mid-slide.
        ignoresMouseEvents = configuration.hideOnHover
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = stripView
    }

    /// Clicking an icon must hand focus to the window it stands for, never the overlay.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var onSelect: ((Int) -> Void)? {
        get { stripView.onSelect }
        set { stripView.onSelect = newValue }
    }

    func slide(to rect: NSRect, animated: Bool) {
        guard animated else {
            setFrame(rect, display: false)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(rect, display: false)
        }
    }

    /// The frame is supplied rather than derived, so a parked strip stays parked.
    func apply(render: StripRender, icons: AppIconProvider, screenFrame: NSRect) {
        setFrame(screenFrame, display: false)
        stripView.frame = NSRect(origin: .zero, size: screenFrame.size)
        stripView.apply(render: render, icons: icons)
    }

    static func screenRect(for render: StripRender, primaryDisplayHeight: Double) -> NSRect {
        let rect = Geometry.appKitRect(
            fromYabai: render.layout.frame,
            primaryDisplayHeight: primaryDisplayHeight
        )
        return NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}
