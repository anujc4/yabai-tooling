import Foundation

// uint32 LE payload length, then NUL-terminated argv plus one extra NUL; see
// docs/SPEC.md § yabai IPC.
enum YabaiWireFormat {
    static let failureByte: UInt8 = 0x07

    static func encode(_ command: YabaiCommand) -> Data {
        encode(argv: command.argv)
    }

    /// NUL is the argv delimiter, so an element carrying one would silently become
    /// several on the wire.
    static func containsDelimiter(_ argv: [String]) -> Bool {
        argv.contains { $0.utf8.contains(0) }
    }

    static func encode(argv: [String]) -> Data {
        var payload = Data()
        for argument in argv {
            payload.append(contentsOf: argument.utf8)
            payload.append(0)
        }
        payload.append(0)

        var message = withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Data($0) }
        message.append(payload)
        return message
    }

    static func validate(response: Data) throws -> Data {
        guard response.first == failureByte else { return response }
        let message = String(decoding: response.dropFirst(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw YabaiError.remoteFailure(message)
    }
}
