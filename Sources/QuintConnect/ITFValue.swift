import Foundation

/// A value in the Informal Trace Format (ITF) that Quint writes with `--out-itf`.
///
/// ITF is JSON with a few tagged encodings for the types JSON lacks: `{"#bigint": "42"}`, `{"#tup": [...]}`,
/// `{"#set": [...]}`, `{"#map": [[k, v], ...]}` and `{"#unserializable": "..."}`. Quint sum types arrive as
/// records with `tag` and `value` fields, which ``variant`` and ``isOption`` expose.
public indirect enum ITFValue: Equatable, Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    /// An integer that does not fit in `Int`, kept as its decimal text.
    case bigInt(String)
    case string(String)
    case list([ITFValue])
    case tuple([ITFValue])
    case set(Set<ITFValue>)
    case map([ITFValue: ITFValue])
    case record([String: ITFValue])
    case unserializable(String)
}

extension ITFValue {
    /// Parses one ITF value from JSON data.
    public init(json: Data) throws {
        let node: JSONNode
        do {
            node = try JSONDecoder().decode(JSONNode.self, from: json)
        } catch {
            throw QuintConnectError.malformedTrace("Not valid JSON: \(error.localizedDescription)")
        }
        self = try ITFValue(node: node)
    }

    /// The fields of a record value.
    public var fields: [String: ITFValue]? {
        if case .record(let fields) = self { return fields }
        return nil
    }

    /// The value of a record field, or `nil` when this is not a record or has no such field.
    public subscript(field: String) -> ITFValue? { fields?[field] }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The tag and payload of a Quint sum-type variant, which ITF encodes as `{tag, value}`.
    public var variant: (tag: String, value: ITFValue)? {
        guard case .record(let fields) = self, fields.count == 2, case .string(let tag)? = fields["tag"],
            let value = fields["value"]
        else { return nil }
        return (tag, value)
    }

    /// Whether this is the Quint `Option` variant `Some(_)` or `None`.
    public var isOption: Bool { variant.map { ["Some", "None"].contains($0.tag) } ?? false }

    /// The payload of `Some(x)`, `nil` for `None`, and the value itself for anything that is not an option.
    public var unwrappingOption: ITFValue? {
        guard let variant, ["Some", "None"].contains(variant.tag) else { return self }
        return variant.tag == "Some" ? variant.value : nil
    }
}

extension ITFValue: CustomStringConvertible {
    /// A compact, Quint-like rendering used in error messages.
    public var description: String {
        switch self {
        case .bool(let value): return String(value)
        case .int(let value): return String(value)
        case .bigInt(let text): return text
        case .string(let text): return "\"\(text)\""
        case .list(let items): return "[" + items.map(\.description).joined(separator: ", ") + "]"
        case .tuple(let items): return "(" + items.map(\.description).joined(separator: ", ") + ")"
        case .set(let items): return "Set(" + items.map(\.description).sorted().joined(separator: ", ") + ")"
        case .map(let entries):
            let pairs = entries.map { "\($0.key) -> \($0.value)" }.sorted()
            return "Map(" + pairs.joined(separator: ", ") + ")"
        case .record(let fields):
            let pairs = fields.keys.sorted().map { "\($0): \(fields[$0]?.description ?? "")" }
            return "{ " + pairs.joined(separator: ", ") + " }"
        case .unserializable(let text): return "<unserializable: \(text)>"
        }
    }
}

// MARK: - JSON bridge

/// The JSON structure ITF is written in, decoded before the ITF-specific tags are interpreted.
enum JSONNode: Decodable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONNode])
    case object([String: JSONNode])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONNode].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONNode].self))
        }
    }
}

extension ITFValue {
    init(node: JSONNode) throws {
        switch node {
        case .null: throw QuintConnectError.malformedTrace("ITF has no null value")
        case .bool(let value): self = .bool(value)
        case .int(let value): self = .int(value)
        case .double(let value): throw QuintConnectError.malformedTrace("ITF has no floating-point value: \(value)")
        case .string(let value): self = .string(value)
        case .array(let items): self = .list(try items.map(ITFValue.init(node:)))
        case .object(let object): self = try ITFValue(object: object)
        }
    }

    private init(object: [String: JSONNode]) throws {
        guard object.count == 1, let (key, payload) = object.first, key.hasPrefix("#") else {
            self = .record(try object.mapValues(ITFValue.init(node:)))
            return
        }
        switch (key, payload) {
        case ("#bigint", .string(let digits)):
            self = Int(digits).map(ITFValue.int) ?? .bigInt(digits)
        case ("#tup", .array(let items)):
            self = .tuple(try items.map(ITFValue.init(node:)))
        case ("#set", .array(let items)):
            self = .set(Set(try items.map(ITFValue.init(node:))))
        case ("#map", .array(let pairs)):
            self = .map(try Self.entries(of: pairs))
        case ("#unserializable", .string(let text)):
            self = .unserializable(text)
        default:
            // `#meta` and any future tag stay ordinary fields.
            self = .record(try object.mapValues(ITFValue.init(node:)))
        }
    }

    private static func entries(of pairs: [JSONNode]) throws -> [ITFValue: ITFValue] {
        var entries: [ITFValue: ITFValue] = [:]
        for pair in pairs {
            guard case .array(let kv) = pair, kv.count == 2 else {
                throw QuintConnectError.malformedTrace("A #map entry must be a [key, value] pair")
            }
            entries[try ITFValue(node: kv[0])] = try ITFValue(node: kv[1])
        }
        return entries
    }
}
