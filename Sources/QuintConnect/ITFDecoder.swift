import Foundation

extension ITFValue {
    /// Decodes this value with `Decodable`.
    ///
    /// | ITF value | Decodes as |
    /// | --- | --- |
    /// | `bool`, `int`, `string` | `Bool`, any integer type, `String` |
    /// | list, tuple, set | an array or a `Set` (a set is read in a stable order) |
    /// | record | a keyed container, so a `struct` |
    /// | map with string or integer keys | a `[String: V]` or `[Int: V]` |
    /// | map with other keys | a dictionary of alternating keys and values, as `Dictionary` expects |
    /// | `Some(x)` and `None` | `Optional` |
    /// | a variant with no payload | the tag as a `String`, so a `String`-backed `enum` |
    ///
    /// A variant with a payload is a record with `tag` and `value` fields, so decode it with a custom
    /// `init(from:)`.
    public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        do {
            return try T(from: ITFDecoder(self, path: []))
        } catch let error as DecodingError {
            throw QuintConnectError.decoding("\(error)")
        }
    }
}

struct ITFDecoder: Decoder {
    let value: ITFValue
    let codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    /// `Some(x)` decodes as `x`, so an `Optional` sees the payload and `None` sees `decodeNil`.
    init(_ value: ITFValue, path: [CodingKey]) {
        if let variant = value.variant, variant.tag == "Some" {
            self.value = variant.value
        } else {
            self.value = value
        }
        self.codingPath = path
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        switch value {
        case .record(let fields):
            return KeyedDecodingContainer(KeyedContainer<Key>(fields: fields, codingPath: codingPath))
        case .map(let entries):
            var fields: [String: ITFValue] = [:]
            for (key, entry) in entries {
                switch key {
                case .string(let name): fields[name] = entry
                case .int(let number): fields[String(number)] = entry
                default: throw mismatch("a map keyed by strings or integers")
                }
            }
            return KeyedDecodingContainer(KeyedContainer<Key>(fields: fields, codingPath: codingPath))
        default:
            throw mismatch("a record")
        }
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        switch value {
        case .list(let items), .tuple(let items):
            return UnkeyedContainer(items: items, codingPath: codingPath)
        case .set(let items):
            return UnkeyedContainer(items: items.sorted { $0.description < $1.description }, codingPath: codingPath)
        case .map(let entries):
            let pairs = entries.sorted { $0.key.description < $1.key.description }
            return UnkeyedContainer(items: pairs.flatMap { [$0.key, $0.value] }, codingPath: codingPath)
        default:
            throw mismatch("a list, tuple, set or map")
        }
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        SingleContainer(value: value, codingPath: codingPath)
    }

    private func mismatch(_ expected: String) -> DecodingError {
        .typeMismatch(Any.self, .init(codingPath: codingPath, debugDescription: "Expected \(expected), found \(value)"))
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func mismatch<T>(_ type: T.Type, _ value: ITFValue, _ path: [CodingKey]) -> DecodingError {
    .typeMismatch(type, .init(codingPath: path, debugDescription: "Cannot decode \(value) as \(type)"))
}

// MARK: - Single value

private struct SingleContainer: SingleValueDecodingContainer {
    let value: ITFValue
    let codingPath: [CodingKey]

    func decodeNil() -> Bool { value.variant?.tag == "None" }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard case .bool(let flag) = value else { throw mismatch(type, value, codingPath) }
        return flag
    }

    func decode(_ type: String.Type) throws -> String {
        if case .string(let text) = value { return text }
        if let variant = value.variant, case .tuple(let payload) = variant.value, payload.isEmpty { return variant.tag }
        throw mismatch(type, value, codingPath)
    }

    func decode(_ type: Double.Type) throws -> Double {
        guard case .int(let number) = value else { throw mismatch(type, value, codingPath) }
        return Double(number)
    }

    func decode(_ type: Float.Type) throws -> Float { Float(try decode(Double.self)) }
    func decode(_ type: Int.Type) throws -> Int { try integer(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try integer(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try integer(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try integer(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try integer(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try integer(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try integer(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try integer(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try integer(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try integer(type) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: ITFDecoder(value, path: codingPath))
    }

    private func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        switch value {
        case .int(let number):
            guard let converted = T(exactly: number) else { throw mismatch(type, value, codingPath) }
            return converted
        case .bigInt(let digits):
            guard let converted = T(digits) else { throw mismatch(type, value, codingPath) }
            return converted
        default:
            throw mismatch(type, value, codingPath)
        }
    }
}

// MARK: - Keyed

private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let fields: [String: ITFValue]
    let codingPath: [CodingKey]

    var allKeys: [Key] { fields.keys.compactMap { Key(stringValue: $0) } }

    func contains(_ key: Key) -> Bool { fields[key.stringValue] != nil }

    func decodeNil(forKey key: Key) throws -> Bool {
        try field(key).variant?.tag == "None"
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try value(type, key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try value(type, key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try value(type, key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try value(type, key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try value(type, key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try value(type, key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try value(type, key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try value(type, key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try value(type, key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try value(type, key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try value(type, key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try value(type, key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try value(type, key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try value(type, key) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try value(type, key) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws
        -> KeyedDecodingContainer<NestedKey>
    {
        try ITFDecoder(field(key), path: codingPath + [key]).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try ITFDecoder(field(key), path: codingPath + [key]).unkeyedContainer()
    }

    func superDecoder() throws -> Decoder { ITFDecoder(.record(fields), path: codingPath) }
    func superDecoder(forKey key: Key) throws -> Decoder { ITFDecoder(try field(key), path: codingPath + [key]) }

    private func field(_ key: Key) throws -> ITFValue {
        guard let value = fields[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key, .init(codingPath: codingPath, debugDescription: "No field `\(key.stringValue)` in the record"))
        }
        return value
    }

    private func value<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T {
        try T(from: ITFDecoder(field(key), path: codingPath + [key]))
    }
}

// MARK: - Unkeyed

private struct UnkeyedContainer: UnkeyedDecodingContainer {
    let items: [ITFValue]
    let codingPath: [CodingKey]
    private(set) var currentIndex = 0

    init(items: [ITFValue], codingPath: [CodingKey]) {
        self.items = items
        self.codingPath = codingPath
    }

    var count: Int? { items.count }
    var isAtEnd: Bool { currentIndex >= items.count }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { throw exhausted(Any.self) }
        guard items[currentIndex].variant?.tag == "None" else { return false }
        currentIndex += 1
        return true
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try next(type) }
    mutating func decode(_ type: String.Type) throws -> String { try next(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try next(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try next(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try next(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try next(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try next(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try next(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try next(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try next(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try next(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try next(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try next(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try next(type) }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try next(type) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws
        -> KeyedDecodingContainer<NestedKey>
    {
        try nextDecoder().container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        try nextDecoder().unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder { try nextDecoder() }

    private mutating func nextDecoder() throws -> ITFDecoder {
        guard !isAtEnd else { throw exhausted(Any.self) }
        defer { currentIndex += 1 }
        return ITFDecoder(items[currentIndex], path: codingPath + [AnyKey(intValue: currentIndex)])
    }

    private mutating func next<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: nextDecoder())
    }

    private func exhausted<T>(_ type: T.Type) -> DecodingError {
        .valueNotFound(type, .init(codingPath: codingPath, debugDescription: "No more elements"))
    }
}
