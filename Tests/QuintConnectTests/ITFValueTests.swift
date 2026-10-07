import Foundation
import Testing

@testable import QuintConnect

struct ITFValueTests {
    private func parse(_ json: String) throws -> ITFValue {
        try ITFValue(json: Data(json.utf8))
    }

    @Test func parsesPlainJSONTypes() throws {
        #expect(try parse("true") == .bool(true))
        #expect(try parse("42") == .int(42))
        #expect(try parse("\"hi\"") == .string("hi"))
        #expect(try parse("[1, 2]") == .list([.int(1), .int(2)]))
    }

    @Test func parsesBigintAsIntWhenItFitsAndTextWhenItDoesNot() throws {
        #expect(try parse(##"{"#bigint": "42"}"##) == .int(42))
        #expect(try parse(##"{"#bigint": "-7"}"##) == .int(-7))
        #expect(
            try parse(##"{"#bigint": "123456789012345678901234567890"}"##) == .bigInt("123456789012345678901234567890"))
    }

    @Test func parsesTuplesSetsAndMaps() throws {
        #expect(try parse(##"{"#tup": [1, true]}"##) == .tuple([.int(1), .bool(true)]))
        #expect(try parse(##"{"#set": [2, 1, 2]}"##) == .set([.int(1), .int(2)]))
        let map = try parse(##"{"#map": [["a", 1], ["b", 2]]}"##)
        #expect(map == .map([.string("a"): .int(1), .string("b"): .int(2)]))
    }

    @Test func setsIgnoreOrder() throws {
        #expect(try parse(##"{"#set": [1, 2, 3]}"##) == parse(##"{"#set": [3, 1, 2]}"##))
    }

    @Test func parsesRecordsAndKeepsMetaAsAField() throws {
        let value = try parse(##"{"#meta": {"index": 0}, "x": 1}"##)
        #expect(value["x"] == .int(1))
        #expect(value["#meta"]?["index"] == .int(0))
    }

    @Test func keepsUnserializableValues() throws {
        #expect(try parse(##"{"#unserializable": "lambda"}"##) == .unserializable("lambda"))
    }

    @Test func recognisesSumTypeVariants() throws {
        let idle = try parse(##"{"tag": "Idle", "value": {"#tup": []}}"##)
        #expect(idle.variant?.tag == "Idle")
        #expect(idle.variant?.value == .tuple([]))
        #expect(try parse(##"{"tag": "x"}"##).variant == nil)
    }

    @Test func unwrapsOptions() throws {
        let some = try parse(##"{"tag": "Some", "value": 3}"##)
        let none = try parse(##"{"tag": "None", "value": {"#tup": []}}"##)
        #expect(some.unwrappingOption == .int(3))
        #expect(none.unwrappingOption == nil)
        #expect(ITFValue.int(5).unwrappingOption == .int(5))
        #expect(some.isOption && none.isOption)
    }

    @Test func rejectsNullFloatsAndBadMaps() {
        #expect(throws: QuintConnectError.self) { try parse("null") }
        #expect(throws: QuintConnectError.self) { try parse("1.5") }
        #expect(throws: QuintConnectError.self) { try parse(##"{"#map": [["only-key"]]}"##) }
        #expect(throws: QuintConnectError.self) { try parse("{not json") }
    }

    @Test func rendersReadableDescriptions() throws {
        let value = try parse(##"{"b": {"#set": [2, 1]}, "a": {"#tup": [true]}}"##)
        #expect(value.description == "{ a: (true), b: Set(1, 2) }")
    }
}
