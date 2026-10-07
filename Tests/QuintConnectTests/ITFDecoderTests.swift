import Foundation
import Testing

@testable import QuintConnect

struct ITFDecoderTests {
    private func parse(_ json: String) throws -> ITFValue {
        try ITFValue(json: Data(json.utf8))
    }

    enum Phase: String, Decodable, Equatable {
        case idle = "Idle"
        case recording = "Recording"
    }

    struct Machine: Decodable, Equatable {
        let phase: Phase
        let mic: Bool
        let count: Int
        let note: String?
        let tags: Set<String>
    }

    @Test func decodesARecordIntoAStruct() throws {
        let json = """
            {"phase": {"tag": "Recording", "value": {"#tup": []}}, "mic": true, "count": {"#bigint": "3"},
             "note": {"tag": "Some", "value": "hi"}, "tags": {"#set": ["a", "b"]}}
            """
        let machine = try parse(json).decode(Machine.self)
        #expect(machine == Machine(phase: .recording, mic: true, count: 3, note: "hi", tags: ["a", "b"]))
    }

    @Test func decodesNoneAsNil() throws {
        let json = """
            {"phase": {"tag": "Idle", "value": {"#tup": []}}, "mic": false, "count": 0,
             "note": {"tag": "None", "value": {"#tup": []}}, "tags": {"#set": []}}
            """
        #expect(try parse(json).decode(Machine.self).note == nil)
    }

    @Test func decodesListsTuplesAndSets() throws {
        #expect(try parse("[1, 2, 3]").decode([Int].self) == [1, 2, 3])
        #expect(try parse(##"{"#tup": [1, 2]}"##).decode([Int].self) == [1, 2])
        #expect(try parse(##"{"#set": [3, 1]}"##).decode(Set<Int>.self) == [1, 3])
    }

    @Test func decodesMapsWithStringAndIntegerKeys() throws {
        #expect(try parse(##"{"#map": [["a", 1]]}"##).decode([String: Int].self) == ["a": 1])
        #expect(try parse(##"{"#map": [[1, "x"], [2, "y"]]}"##).decode([Int: String].self) == [1: "x", 2: "y"])
    }

    @Test func decodesIntegerWidthsAndRejectsOverflow() throws {
        #expect(try parse("200").decode(UInt8.self) == 200)
        #expect(throws: QuintConnectError.self) {
            try parse(##"{"#bigint": "123456789012345678901234567890"}"##).decode(Int.self)
        }
    }

    @Test func reportsATypeMismatch() throws {
        #expect(throws: QuintConnectError.self) { try parse("\"text\"").decode(Int.self) }
        #expect(throws: QuintConnectError.self) { try parse("1").decode(Machine.self) }
    }

    @Test func reportsAMissingField() throws {
        #expect(throws: QuintConnectError.self) { try parse(##"{"mic": true}"##).decode(Machine.self) }
    }
}
