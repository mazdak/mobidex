import Foundation

/// Decodes `Decodable` models directly from an already-parsed `JSONValue` tree, replacing the
/// encode-to-Data-then-JSONDecoder round trip that used to run on the main actor for every
/// turn/thread payload (audit P2). Default key/date strategies only — matching the plain
/// `JSONDecoder()` it replaces.
enum JSONValueDecoding {
    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        try T(from: JSONValueDecoder(value: value, codingPath: []))
    }
}

private struct JSONValueDecoder: Decoder {
    let value: JSONValue
    let codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let object) = value else {
            throw typeMismatch([String: JSONValue].self)
        }
        return KeyedDecodingContainer(KeyedContainer(object: object, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .array(let array) = value else {
            throw typeMismatch([JSONValue].self)
        }
        return UnkeyedContainer(array: array, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        SingleValueContainer(value: value, codingPath: codingPath)
    }

    private func typeMismatch(_ expected: Any.Type) -> DecodingError {
        .typeMismatch(expected, .init(codingPath: codingPath, debugDescription: "Found \(value) instead."))
    }
}

private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let object: [String: JSONValue]
    let codingPath: [CodingKey]

    var allKeys: [Key] { object.keys.compactMap(Key.init(stringValue:)) }

    func contains(_ key: Key) -> Bool { object[key.stringValue] != nil }

    private func value(for key: Key) throws -> JSONValue {
        guard let value = object[key.stringValue] else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing key \(key.stringValue)."))
        }
        return value
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        if case .null = try value(for: key) { return true }
        return false
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try T(from: JSONValueDecoder(value: try value(for: key), codingPath: codingPath + [key]))
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try JSONValueDecoder(value: try value(for: key), codingPath: codingPath + [key]).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try JSONValueDecoder(value: try value(for: key), codingPath: codingPath + [key]).unkeyedContainer()
    }

    func superDecoder() throws -> Decoder {
        JSONValueDecoder(value: .object(object), codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        JSONValueDecoder(value: try value(for: key), codingPath: codingPath + [key])
    }
}

private struct UnkeyedContainer: UnkeyedDecodingContainer {
    let array: [JSONValue]
    let codingPath: [CodingKey]
    var currentIndex = 0

    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }

    private struct IndexKey: CodingKey {
        let intValue: Int?
        var stringValue: String { "Index \(intValue ?? 0)" }
        init(intValue: Int) { self.intValue = intValue }
        init?(stringValue: String) { return nil }
    }

    private mutating func nextValue() throws -> JSONValue {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(JSONValue.self, .init(codingPath: codingPath, debugDescription: "Unkeyed container exhausted."))
        }
        defer { currentIndex += 1 }
        return array[currentIndex]
    }

    mutating func decodeNil() throws -> Bool {
        if case .null = array[currentIndex] {
            currentIndex += 1
            return true
        }
        return false
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let index = currentIndex
        return try T(from: JSONValueDecoder(value: try nextValue(), codingPath: codingPath + [IndexKey(intValue: index)]))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        try JSONValueDecoder(value: try nextValue(), codingPath: codingPath).container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        try JSONValueDecoder(value: try nextValue(), codingPath: codingPath).unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder {
        JSONValueDecoder(value: try nextValue(), codingPath: codingPath)
    }
}

private struct SingleValueContainer: SingleValueDecodingContainer {
    let value: JSONValue
    let codingPath: [CodingKey]

    func decodeNil() -> Bool {
        if case .null = value { return true }
        return false
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard case .bool(let bool) = value else { throw mismatch(type) }
        return bool
    }

    func decode(_ type: String.Type) throws -> String {
        guard case .string(let string) = value else { throw mismatch(type) }
        return string
    }

    func decode(_ type: Double.Type) throws -> Double {
        switch value {
        case .double(let double): return double
        case .int(let int): return Double(int)
        default: throw mismatch(type)
        }
    }

    func decode(_ type: Float.Type) throws -> Float { Float(try decode(Double.self)) }

    func decode(_ type: Int.Type) throws -> Int {
        switch value {
        case .int(let int): return int
        case .double(let double) where double == double.rounded() && double >= Double(Int.min) && double <= Double(Int.max):
            return Int(double)
        default: throw mismatch(type)
        }
    }

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
        try T(from: JSONValueDecoder(value: value, codingPath: codingPath))
    }

    private func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        guard case .int(let int) = value, let converted = T(exactly: int) else { throw mismatch(type) }
        return converted
    }

    private func mismatch(_ expected: Any.Type) -> DecodingError {
        .typeMismatch(expected, .init(codingPath: codingPath, debugDescription: "Found \(value) instead."))
    }
}
