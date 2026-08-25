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

if arguments.contains("--notify") {
    try? NotificationSocket.notify(
        path: value(after: "--socket") ?? NotificationSocket.defaultPath(),
        event: value(after: "--event")
    )
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

// Starting anyway would unlink the running daemon's socket and replace its signals.
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

// Main queue during operation, then the atexit handler once no other thread is left.
nonisolated(unsafe) var registered = false
nonisolated(unsafe) var tornDown = false

/// A signal that fails to register is an event the daemon never hears about, so
/// failures leave `registered` false and the next refresh retries the table.
func register() {
    var failures: [String] = []
    for event in YabaiSignalEvent.allCases {
        // A SIGKILLed run leaves its signals behind; yabai holds two under one label.
        client.removeSignal(event)
        do {
            try client.addSignal(event, notifying: executable, socket: socketPath)
        } catch {
            failures.append("\(event.rawValue): \(error)")
        }
    }
    for failure in failures {
        FileHandle.standardError.write(Data("yabai-stacks: could not register signal \(failure)\n".utf8))
    }
    registered = failures.isEmpty
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

        // A yabai restart wipes its signal table.
        if !registered { register() }
    } catch {
        registered = false
        FileHandle.standardError.write(Data("yabai-stacks: refresh failed: \(error)\n".utf8))
    }
}

/// yabai emits several signals per user action, and a drag emits one per frame;
/// one repaint per burst is enough.
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
    try socket.listen { name in
        let action = WakeAction.action(for: name)
        DispatchQueue.main.async {
            switch action {
            case .hide: controller.setHidden(true, animated: true)
            case .show: controller.setHidden(false, animated: true)
            case .refresh: scheduleRefresh()
            }
        }
    }
} catch {
    fail("could not open notification socket at \(socketPath): \(error)")
}

register()

// DispatchSource rather than signal(2): the handler runs on a normal queue, so
// it is not restricted to async-signal-safe calls.
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
    MainActor.assumeIsolated { scheduleRefresh() }
}

refresh()
FileHandle.standardError.write(
    Data("yabai-stacks: listening on \(socketPath), \(controller.panelCount) overlay(s)\n".utf8)
)

_ = terminationSources
application.run()
