import AppKit
import Dispatch
import YabaiStacksCore
import YabaiStacksUI

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("yabai-stacks: \(message)\n".utf8))
    exit(1)
}

// Runs once per yabai event and must exit fast; nothing else is set up.
if arguments.contains("--notify") {
    try? NotificationSocket.notify(path: NotificationSocket.defaultPath())
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

// Accessory policy: no Dock icon and no menu bar, so this behaves like borders
// when launched from yabairc.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let controller = OverlayController(configuration: configuration)
controller.onSelect = { id in
    // The only write this program ever performs. Focusing does not change the
    // layout, which is why it is the only non-query command in YabaiCommand.
    try? client.focusWindow(id: id)
}

@MainActor
func refresh() {
    do {
        let windows = try client.windows()
        let spaces = try client.spaces()
        let displays = try client.displays()
        controller.apply(stacks: detector.detect(windows: windows, spaces: spaces), displays: displays)
    } catch {
        // A refresh can race a yabai restart. Dropping one is recoverable; the
        // next event repaints. Exiting would leave the user with no overlays.
        FileHandle.standardError.write(Data("yabai-stacks: refresh failed: \(error)\n".utf8))
    }
}

/// yabai fires several signals for one user action — creating a window emits
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

let socket = NotificationSocket(path: NotificationSocket.defaultPath())
do {
    try socket.listen { DispatchQueue.main.async { scheduleRefresh() } }
} catch {
    fail("could not open notification socket at \(socket.path): \(error)")
}

let executable = CommandLine.arguments.first.map {
    URL(fileURLWithPath: $0).standardizedFileURL.path
} ?? "yabai-stacks"

for event in YabaiSignalEvent.allCases {
    // Replace rather than accumulate: a previous run that was killed leaves its
    // signals behind, and yabai happily registers a second one under the label.
    client.removeSignal(event)
    do {
        try client.addSignal(event, notifying: executable)
    } catch {
        fail("could not register yabai signal \(event.rawValue): \(error)")
    }
}

func teardown() {
    for event in YabaiSignalEvent.allCases { client.removeSignal(event) }
    socket.stop()
}

// DispatchSource rather than signal(2): the handler runs on a normal queue, so
// it can safely talk to yabai and AppKit instead of being async-signal-safe.
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

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.activeSpaceDidChangeNotification,
    object: nil,
    queue: .main
) { _ in
    MainActor.assumeIsolated { scheduleRefresh() }
}

atexit { teardown() }

refresh()
FileHandle.standardError.write(
    Data("yabai-stacks: listening on \(socket.path), \(controller.panelCount) overlay(s)\n".utf8)
)

_ = terminationSources
application.run()
