import Foundation

public struct YabaiFrame: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct YabaiWindow: Codable, Hashable, Sendable {
    public let id: Int
    public let pid: Int
    public let app: String
    public let title: String
    public let frame: YabaiFrame
    public let display: Int
    public let space: Int
    public let level: Int
    public let subrole: String

    /// 0 means unstacked; >= 1 is a 1-based position, returned descending.
    public let stackIndex: Int

    public let isRootWindow: Bool
    public let hasFocus: Bool
    public let isVisible: Bool
    public let isFloating: Bool
    public let isMinimized: Bool
    public let isHidden: Bool
    public let isSticky: Bool

    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, frame, display, space, level, subrole
        case stackIndex = "stack-index"
        case isRootWindow = "root-window"
        case hasFocus = "has-focus"
        case isVisible = "is-visible"
        case isFloating = "is-floating"
        case isMinimized = "is-minimized"
        case isHidden = "is-hidden"
        case isSticky = "is-sticky"
    }

    public init(
        id: Int,
        pid: Int,
        app: String,
        title: String,
        frame: YabaiFrame,
        display: Int,
        space: Int,
        level: Int,
        subrole: String,
        stackIndex: Int,
        isRootWindow: Bool,
        hasFocus: Bool,
        isVisible: Bool,
        isFloating: Bool,
        isMinimized: Bool,
        isHidden: Bool,
        isSticky: Bool
    ) {
        self.id = id
        self.pid = pid
        self.app = app
        self.title = title
        self.frame = frame
        self.display = display
        self.space = space
        self.level = level
        self.subrole = subrole
        self.stackIndex = stackIndex
        self.isRootWindow = isRootWindow
        self.hasFocus = hasFocus
        self.isVisible = isVisible
        self.isFloating = isFloating
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.isSticky = isSticky
    }
}

public struct YabaiSpace: Codable, Hashable, Sendable {
    public let uuid: String
    public let index: Int
    public let type: String
    public let display: Int
    public let hasFocus: Bool
    public let isVisible: Bool

    enum CodingKeys: String, CodingKey {
        case uuid, index, type, display
        case hasFocus = "has-focus"
        case isVisible = "is-visible"
    }

    public init(uuid: String, index: Int, type: String, display: Int, hasFocus: Bool, isVisible: Bool) {
        self.uuid = uuid
        self.index = index
        self.type = type
        self.display = display
        self.hasFocus = hasFocus
        self.isVisible = isVisible
    }
}

public struct YabaiDisplay: Codable, Hashable, Sendable {
    public let index: Int
    public let uuid: String
    public let frame: YabaiFrame

    public init(index: Int, uuid: String, frame: YabaiFrame) {
        self.index = index
        self.uuid = uuid
        self.frame = frame
    }
}
