import AppKit
import Dispatch
import YabaiStacksCore
import YabaiStacksUI

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("yabai-stacks: \(message)\n".utf8))
    exit(1)
}

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.index(after: index) < arguments.endIndex
    else { return nil }
    return arguments[arguments.index(after: index)]
}

// Runs once per yabai event and must exit fast; nothing else is set up. The
// socket path is passed in rather than re-derived: this runs under yabai's
// environment, which need not carry USER or any override the daemon saw.
if arguments.contains("--notify") {
    try? NotificationSocket.notify(path: value(after: "--socket") ?? NotificationSocket.defaultPath())
    exit(0)
}

let intent: CommandLineIntent
do {
    intent = try ConfigurationParser.parse(arguments)
} catch {
    fail(String(describing: error))
}

let configuration: Configuration
switch intent {
case .help:
    print(ConfigurationParser.usage)
    exit(0)
case .version:
    print("yabai-stacks \(YabaiStacks.version)")
    exit(0)
case .run(let parsed):
    configuration = parsed
}

let client = YabaiClient(transport: YabaiSocketTransport())
let detector = StackDetector(minStackSize: configuration.minStackSize)
let socketPath = NotificationSocket.defaultPath()

// Another daemon holding the socket would otherwise be silently disabled: our
// listen() unlinks the path, and our registration loop replaces its signals.
if NotificationSocket.isServed(path: socketPath) {
    fail("another yabai-stacks is already running on \(socketPath)")
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let controller = OverlayController(configuration: configuration)
controller.onSelect = { id in
    try? client.focusWindow(id: id)
}

let socket = NotificationSocket(path: socketPath)
let executable = ExecutablePath.resolved(argv0: CommandLine.arguments.first)

// Touched from the main queue during normal operation and once more from the
// atexit handler, by which point every other thread is gone.
nonisolated(unsafe) var registered = false
nonisolated(unsafe) var tornDown = false

func register() {
    for event in YabaiSignalEvent.allCases {
        // Replace rather than accumulate: a run killed with SIGKILL leaves its
        // signals behind, and yabai will happily hold two under one label.
        client.removeSignal(event)
        try? client.addSignal(event, notifying: executable, socket: socketPath)
    }
    registered = true
}

func teardown() {
    guard !tornDown else { return }
    tornDown = true
    for event in YabaiSignalEvent.allCases { client.removeSignal(event) }
    socket.stop()
}

atexit { teardown() }

@MainActor
func refresh() {
    do {
        let windows = try client.windows()
        let spaces = try client.spaces()
        let displays = try client.displays()
        controller.apply(stacks: detector.detect(windows: windows, spaces: spaces), displays: displays)

        // A yabai restart wipes its signal table, so a refresh that succeeds
        // after a failure is the moment to put our signals back.
        if !registered { register() }
    } catch {
        // Dropping one repaint is recoverable; the next event repaints. Exiting
        // would leave the user with no overlays at all.
        registered = false
        FileHandle.standardError.write(Data("yabai-stacks: refresh failed: \(error)\n".utf8))
    }
}

/// yabai emits several signals per user action — creating a window fires
/// window_created, then window_focused, then application_front_switched. One
/// repaint per burst is enough, and coalescing keeps a drag from re-querying
/// on every frame.
let coalesceInterval = DispatchTimeInterval.milliseconds(40)
var pending: DispatchWorkItem?

@MainActor
func scheduleRefresh() {
    pending?.cancel()
    let work = DispatchWorkItem { refresh() }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + coalesceInterval, execute: work)
}

do {
    try socket.listen { DispatchQueue.main.async { scheduleRefresh() } }
} catch {
    fail("could not open notification socket at \(socketPath): \(error)")
}

register()

// DispatchSource rather than signal(2): the handler runs on a normal queue, so
// it can talk to yabai and AppKit instead of being restricted to
// async-signal-safe calls.
let terminationSources = [SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        teardown()
        exit(0)
    }
    source.resume()
    return source
}

let workspace = NSWorkspace.shared.notificationCenter
workspace.addObserver(
    forName: NSWorkspace.activeSpaceDidChangeNotification,
    object: nil,
    queue: .main
) { _ in
    MainActor.assumeIsolated {
        controller.setHidden(false, animated: true)
        scheduleRefresh()
    }
}

// Mission Control has no public API. The Dock takes over the screen for its
// duration, so its activation is the closest observable proxy; the overlays
// slide away while it is up and return when the Dock resigns.
workspace.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { note in
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          app.bundleIdentifier == "com.apple.dock"
    else { return }
    MainActor.assumeIsolated { controller.setHidden(true, animated: true) }
}

workspace.addObserver(
    forName: NSWorkspace.didDeactivateApplicationNotification,
    object: nil,
    queue: .main
) { note in
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          app.bundleIdentifier == "com.apple.dock"
    else { return }
    MainActor.assumeIsolated {
        controller.setHidden(false, animated: true)
        scheduleRefresh()
    }
}

refresh()
FileHandle.standardError.write(
    Data("yabai-stacks: listening on \(socketPath), \(controller.panelCount) overlay(s)\n".utf8)
)

_ = terminationSources
application.run()
