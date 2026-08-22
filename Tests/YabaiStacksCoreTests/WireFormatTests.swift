import Foundation
import Testing
@testable import YabaiStacksCore

@Suite("yabai v7.1.24 wire framing")
struct WireFormatTests {
    /// Golden bytes captured from the real `yabai -m query --displays --space 1`
    /// client by standing in for the daemon socket. Any drift breaks this test.
    @Test("encoding reproduces the real client's bytes")
    func goldenBytes() {
        let expected = Data([
            0x1c, 0x00, 0x00, 0x00,
            0x71, 0x75, 0x65, 0x72, 0x79, 0x00,                                     // "query\0"
            0x2d, 0x2d, 0x64, 0x69, 0x73, 0x70, 0x6c, 0x61, 0x79, 0x73, 0x00,       // "--displays\0"
            0x2d, 0x2d, 0x73, 0x70, 0x61, 0x63, 0x65, 0x00,                         // "--space\0"
            0x31, 0x00,                                                             // "1\0"
            0x00,                                                                   // list terminator
        ])

        #expect(YabaiWireFormat.encode(argv: ["query", "--displays", "--space", "1"]) == expected)
    }

    @Test("encoding a command routes through the same framing")
    func commandEncoding() {
        #expect(
            YabaiWireFormat.encode(.query(.windows(.space(2))))
                == YabaiWireFormat.encode(argv: ["query", "--windows", "--space", "2"])
        )
        #expect(
            YabaiWireFormat.encode(.focusWindow(id: 577003))
                == YabaiWireFormat.encode(argv: ["window", "--focus", "577003"])
        )
    }

    @Test("length prefix is little-endian and counts the payload only")
    func lengthPrefix() {
        let message = YabaiWireFormat.encode(argv: ["query", "--windows"])
        let prefix = message.prefix(4)
        let payload = message.dropFirst(4)

        #expect(prefix == Data([0x11, 0x00, 0x00, 0x00]))
        #expect(payload.count == 17)
        #expect(UInt32(littleEndian: prefix.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }) == 17)
        #expect(Array(payload) == Array("query\u{0}--windows\u{0}\u{0}".utf8))
    }

    @Test("each argument is NUL terminated and the list gets one extra NUL")
    func nulTermination() {
        let payload = YabaiWireFormat.encode(argv: ["a", "bb"]).dropFirst(4)
        #expect(Array(payload) == [0x61, 0x00, 0x62, 0x62, 0x00, 0x00])
    }

    @Test("empty argv still carries the list terminator")
    func emptyArgv() {
        #expect(Array(YabaiWireFormat.encode(argv: [])) == [0x01, 0x00, 0x00, 0x00, 0x00])
    }

    @Test("non-ASCII arguments are encoded as UTF-8")
    func utf8Arguments() {
        #expect(Array(YabaiWireFormat.encode(argv: ["é"]).dropFirst(4)) == [0xc3, 0xa9, 0x00, 0x00])
    }

    @Test("a successful response passes through untouched")
    func successResponse() throws {
        let payload = Data("[{\"id\":1}]\n".utf8)
        #expect(try YabaiWireFormat.validate(response: payload) == payload)
        #expect(try YabaiWireFormat.validate(response: Data()) == Data())
    }

    @Test("a 0x07-prefixed response becomes a remoteFailure carrying yabai's message")
    func failureResponse() {
        // Real daemon replies, captured live.
        let unknownCommand = Data([0x07]) + Data("unknown command '--bogus' for domain 'query'\n".utf8)
        let missingWindow = Data([0x07]) + Data("could not locate window with the specified id '999999999'.\n".utf8)

        #expect(throws: YabaiError.remoteFailure("unknown command '--bogus' for domain 'query'")) {
            try YabaiWireFormat.validate(response: unknownCommand)
        }
        #expect(throws: YabaiError.remoteFailure("could not locate window with the specified id '999999999'.")) {
            try YabaiWireFormat.validate(response: missingWindow)
        }
    }
}

@Suite("Socket path resolution")
struct SocketPathTests {
    @Test("defaults to /tmp/yabai_$USER.socket")
    func defaultPath() {
        #expect(YabaiSocketTransport.defaultPath(environment: ["USER": "someone"]) == "/tmp/yabai_someone.socket")
    }

    @Test("YABAI_SOCKET overrides the default")
    func override() {
        let environment = ["USER": "someone", "YABAI_SOCKET": "/tmp/test.socket"]
        #expect(YabaiSocketTransport.defaultPath(environment: environment) == "/tmp/test.socket")
        #expect(YabaiSocketTransport(path: "/tmp/explicit.socket").path == "/tmp/explicit.socket")
    }

    @Test("an empty override is ignored")
    func emptyOverride() {
        let environment = ["USER": "someone", "YABAI_SOCKET": ""]
        #expect(YabaiSocketTransport.defaultPath(environment: environment) == "/tmp/yabai_someone.socket")
    }
}
