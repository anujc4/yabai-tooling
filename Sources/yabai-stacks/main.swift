import AppKit
import YabaiStacksCore
import YabaiStacksUI

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("yabai-stacks: \(message)\n".utf8))
    exit(1)
}

let intent: CommandLineIntent
do {
    intent = try ConfigurationParser.parse(arguments.filter { $0 != "--once" })
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

func currentStacks() throws -> (stacks: [Stack], displays: [YabaiDisplay]) {
    let windows = try client.windows()
    let spaces = try client.spaces()
    let displays = try client.displays()
    let detector = StackDetector(minStackSize: configuration.minStackSize)
    return (detector.detect(windows: windows, spaces: spaces), displays)
}

// No Dock icon and no menu bar: this runs as a background process launched from
// yabairc, the same way borders does.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let controller = OverlayController(configuration: configuration)

do {
    let current = try currentStacks()
    controller.apply(stacks: current.stacks, displays: current.displays)
    FileHandle.standardError.write(Data("yabai-stacks: rendering \(controller.panelCount) stack overlay(s)\n".utf8))
} catch {
    fail(String(describing: error))
}

application.run()
