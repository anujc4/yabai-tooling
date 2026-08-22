import AppKit
import YabaiStacksCore

extension RGBAColor {
    var cgColor: CGColor {
        CGColor(red: redFraction, green: greenFraction, blue: blueFraction, alpha: alphaFraction)
    }
}

/// Draws one strip. Icons are `CALayer` contents rather than `drawRect` output,
/// so a refresh that only changes the highlight is a compositing change and
/// never a redraw.
final class StripView: NSView {
    private let configuration: Configuration
    private let background = CALayer()
    private var iconLayers: [CALayer] = []
    private var highlight = CALayer()

    private(set) var render: StripRender

    /// Set by the owning panel; turns a click into a yabai focus request.
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

    /// Icon rects are computed in yabai's top-left-origin space, so the view
    /// has to share that origin. Unflipped, a vertical strip would render its
    /// first member at the bottom, and clicks would agree with the wrong order.
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
        background.borderWidth = configuration.borderWidth
        background.borderColor = configuration.activeColor.cgColor

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
            // A pid whose app quit mid-refresh has no icon; the slot stays blank
            // rather than shifting every icon after it out of alignment.
            layer.isHidden = layer.contents == nil
        }
    }

    /// The active member is ringed rather than tinted, so the icon itself stays
    /// recognisable. A stack on a visible but unfocused space has none (SPEC 5).
    private func layoutHighlight(render: StripRender) {
        guard let active = render.layout.activeIndex else {
            highlight.isHidden = true
            return
        }
        let inset = max(1, configuration.borderWidth)
        highlight.isHidden = false
        highlight.frame = localRect(at: active, in: render).insetBy(dx: -inset, dy: -inset)
        highlight.borderColor = configuration.activeColor.cgColor
        highlight.borderWidth = inset
        highlight.cornerRadius = min(inset * 2, configuration.cornerRadius)
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

/// A borderless, non-activating panel sized exactly to its strip. Sizing it to
/// the strip rather than the window is what lets it take clicks without an
/// event tap or an Accessibility grant, while leaving the rest of the window
/// untouched.
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
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = stripView
    }

    /// Clicking an icon must never move focus to the overlay itself — the whole
    /// point is to hand focus to the window the icon stands for.
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

    func apply(render: StripRender, icons: AppIconProvider, primaryDisplayHeight: Double) {
        setFrame(Self.screenRect(for: render, primaryDisplayHeight: primaryDisplayHeight), display: false)
        stripView.frame = NSRect(origin: .zero, size: frame.size)
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
