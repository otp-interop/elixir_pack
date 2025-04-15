import Observation
import Foundation
import Combine
import erlang

extension Array {
    init<Tuple>(tuple: Tuple, start: KeyPath<Tuple, Element>) {
        self = withUnsafePointer(to: tuple) { pointer in
            return [Element](UnsafeBufferPointer(
                start: pointer.pointer(to: start)!,
                count: MemoryLayout.size(ofValue: pointer.pointee) / MemoryLayout.size(ofValue: pointer.pointee[keyPath: start])
            ))
        }
    }
}

/// A generic type that can be returned by an ``ErlangNode`` representing any
/// term.
public enum Term: Sendable, Hashable, CustomDebugStringConvertible {
    case int(Int)
    case double(Double)
    
    case atom(String)
    
    case string(String)
    
    case ref(Reference)
    
    case port(Port)
    
    case pid(PID)
    
    case tuple([Term])
    
    case list([Term])
    
    case binary(Data)
    
    case bitstring(Data)
    
    case function(Function)
    
    case map([Term:Term])
    
    public struct Reference: Sendable, Hashable {
        var ref: erlang_ref
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            var lhs = lhs
            var rhs = rhs
            return ei_cmp_refs(&lhs.ref, &rhs.ref) == 0
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(ref.creation)
            hasher.combine(ref.len)
            hasher.combine(Array(tuple: ref.n, start: \.0))
            hasher.combine(Array(tuple: ref.node, start: \.0))
        }
    }
    
    public struct Port: Sendable, Hashable {
        var port: erlang_port
    
        public static func == (lhs: Self, rhs: Self) -> Bool {
            var lhs = lhs
            var rhs = rhs
            return ei_cmp_ports(&lhs.port, &rhs.port) == 0
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(port.creation)
            hasher.combine(port.id)
            hasher.combine(Array(tuple: port.node, start: \.0))
        }
    }
    
    public struct PID: Sendable, Hashable {
        var pid: erlang_pid
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            var lhs = lhs
            var rhs = rhs
            return ei_cmp_pids(&lhs.pid, &rhs.pid) == 0
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(pid.creation)
            hasher.combine(pid.num)
            hasher.combine(pid.serial)
            hasher.combine(Array(tuple: pid.node, start: \.0))
        }
    }
    
    public final class Function: @unchecked Sendable, Hashable {
        var fun: erlang_fun
        
        init(fun: erlang_fun) {
            self.fun = fun
        }
        
        deinit {
            free_fun(&fun)
        }
        
        public static func == (lhs: Function, rhs: Function) -> Bool {
            lhs.hashValue == rhs.hashValue
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(fun.arity)
            hasher.combine(fun.type)
            hasher.combine(Array(tuple: fun.module, start: \.0))
            
            hasher.combine(fun.u.closure.free_var_len)
            hasher.combine(fun.u.closure.free_vars)
            hasher.combine(fun.u.closure.index)
            hasher.combine(fun.u.closure.n_free_vars)
            hasher.combine(fun.u.closure.old_index)
            hasher.combine(fun.u.closure.old_index)
            hasher.combine(fun.u.closure.uniq)
            hasher.combine(Array(tuple: fun.u.closure.md5, start: \.0))
            hasher.combine(PID(pid: fun.u.closure.pid))
            
            hasher.combine(fun.u.exprt.func)
            hasher.combine(fun.u.exprt.func_allocated)
        }
    }
    
    func encode(to buffer: inout ei_x_buff, initializeBuffer: Bool = true) throws {
        if initializeBuffer {
            guard ei_x_new_with_version(&buffer) == 0
            else { throw TermError.encodingError }
        }
        
        switch self {
        case let .int(int):
            guard ei_x_encode_long(&buffer, int) == 0
            else { throw TermError.encodingError }
        case let .double(double):
            guard ei_x_encode_double(&buffer, double) == 0
            else { throw TermError.encodingError }
        case let .atom(atom):
            guard ei_x_encode_atom(&buffer, strdup(atom)) == 0
            else { throw TermError.encodingError }
        case var .ref(ref):
            guard ei_x_encode_ref(&buffer, &ref.ref) == 0
            else { throw TermError.encodingError }
        case var .port(port):
            guard ei_x_encode_port(&buffer, &port.port) == 0
            else { throw TermError.encodingError }
        case var .pid(pid):
            guard ei_x_encode_pid(&buffer, &pid.pid) == 0
            else { throw TermError.encodingError }
        case let .tuple(terms):
            guard ei_x_encode_tuple_header(&buffer, terms.count) == 0
            else { throw TermError.encodingError }
            for term in terms {
                try term.encode(to: &buffer, initializeBuffer: false)
            }
        case let .list(list) where list.isEmpty:
            guard ei_x_encode_list_header(&buffer, list.count) == 0
            else { throw TermError.encodingError }
        case let .list(list):
            guard ei_x_encode_list_header(&buffer, list.count) == 0
            else { throw TermError.encodingError }
            for term in list {
                try term.encode(to: &buffer, initializeBuffer: false)
            }
            guard ei_x_encode_empty_list(&buffer) == 0
            else { throw TermError.encodingError }
        case let .binary(binary):
            guard binary.withUnsafeBytes({ pointer in
                ei_x_encode_binary(&buffer, pointer.baseAddress!, Int32(pointer.count))
            }) == 0
            else { throw TermError.encodingError }
        case let .bitstring(bitstring):
            guard bitstring.withUnsafeBytes({ pointer in
                ei_x_encode_bitstring(&buffer, pointer.baseAddress!, 0, pointer.count * UInt8.bitWidth)
            }) == 0
            else { throw TermError.encodingError }
        case var .function(function):
            guard ei_x_encode_fun(&buffer, &function.fun) == 0
            else { throw TermError.encodingError }
        case let .map(map):
            guard ei_x_encode_map_header(&buffer, map.count) == 0
            else { throw TermError.encodingError }
            for (key, value) in map {
                try key.encode(to: &buffer, initializeBuffer: false)
                try value.encode(to: &buffer, initializeBuffer: false)
            }
        case let .string(string):
            guard ei_x_encode_string(&buffer, strdup(string)) == 0
            else { throw TermError.encodingError }
        }
    }
    
    public init(
        from buffer: inout ei_x_buff
    ) throws {
        var index: Int32 = 0
        
        var version: Int32 = 0
        ei_decode_version(buffer.buff, &index, &version) == 0
//        guard ei_decode_version(buffer.buff, &index, &version) == 0
//        else { throw TermError.decodingError(.missingVersion) }
        
        func decodeNext() throws -> Self {
            var type: UInt32 = 0
            var size: Int32 = 0
            ei_get_type(buffer.buff, &index, &type, &size)
            
            switch Character(UnicodeScalar(type)!) {
            case "a", "b": // integer
                var int: Int = 0
                guard ei_decode_long(buffer.buff, &index, &int) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .int(int)
            case "c", "F": //  float
                var double: Double = 0
                guard ei_decode_double(buffer.buff, &index, &double) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .double(double)
            case "d", "s", "v": // atom
                var atom: [CChar] = [CChar](repeating: 0, count: Int(MAXATOMLEN))
                guard ei_decode_atom(buffer.buff, &index, &atom) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .atom(String(cString: atom))
            case "e", "r", "Z": // ref
                var ref: erlang_ref = erlang_ref()
                guard ei_decode_ref(buffer.buff, &index, &ref) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .ref(.init(ref: ref))
            case "f", "Y", "x": // port
                var port: erlang_port = erlang_port()
                guard ei_decode_port(buffer.buff, &index, &port) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .port(.init(port: port))
            case "g", "X": // pid
                var pid = erlang_pid()
                guard ei_decode_pid(buffer.buff, &index, &pid) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .pid(.init(pid: pid))
            case "h", "i": // tuple
                var arity: Int32 = 0
                guard ei_decode_tuple_header(buffer.buff, &index, &arity) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .tuple(try (0..<arity).map { _ in
                    try decodeNext()
                })
            case "k": // string
                var string: UnsafeMutablePointer<CChar> = .allocate(capacity: Int(size) + 1)
                defer { string.deallocate() }
                guard ei_decode_string(buffer.buff, &index, string) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .string(String(cString: string))
            case "l": // list
                var arity: Int32 = 0
                guard ei_decode_list_header(buffer.buff, &index, &arity) == 0
                else { throw TermError.decodingError(.badTerm) }
                let elements = try (0..<arity).map { _ in
                    try decodeNext()
                }
                // empty list header at the end
                guard ei_decode_list_header(buffer.buff, &index, &arity) == 0,
                      arity == 0
                else { throw TermError.decodingError(.missingListEnd) }
                return .list(elements)
            case "j": // empty list
                var arity: Int32 = 0
                guard ei_decode_list_header(buffer.buff, &index, &arity) == 0,
                      arity == 0
                else { throw TermError.decodingError(.badTerm) }
                return .list([])
            case "m": // binary
                var binary: UnsafeMutableRawPointer = .allocate(byteCount: Int(size), alignment: 0)
                var length: Int = 0
                guard ei_decode_binary(buffer.buff, &index, binary, &length) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .binary(Data(bytes: binary, count: length))
            case "M": // bit binary
                var pointer: UnsafePointer<CChar>?
                var bitOffset: UInt32 = 0
                var bits: Int = 0
                guard ei_decode_bitstring(buffer.buff, &index, &pointer, &bitOffset, &bits) == 0
                else { throw TermError.decodingError(.badTerm) }
                guard bitOffset == 0
                else { throw TermError.decodingError(.unsupportedBitOffset(bitOffset)) }
                return .bitstring(pointer.map {
                    Data(bytes: $0, count: bits / UInt8.bitWidth)
                } ?? Data())
            case "p", "u", "q": // function
                var fun: erlang_fun = erlang_fun()
                guard ei_decode_fun(buffer.buff, &index, &fun) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .function(.init(fun: fun))
            case "t": // map
                var arity: Int32 = 0
                guard ei_decode_map_header(buffer.buff, &index, &arity) == 0
                else { throw TermError.decodingError(.badTerm) }
                return .map(Dictionary(uniqueKeysWithValues: try (0..<arity).map { _ in
                    let pair = (try decodeNext(), try decodeNext())
                    return pair
                }))
            case let type:
                throw TermError.decodingError(.unknownType(type))
            }
        }
        
        self = try decodeNext()
    }
    
    public func makeBuffer() throws -> ei_x_buff {
        var buffer = ei_x_buff()
        
        try encode(to: &buffer)
        
        return buffer
    }
    
    enum TermError: Error {
        case encodingError
        case decodingError(DecodingError)
        
        enum DecodingError {
            case missingVersion
            case badTerm
            case unknownType(Character)
            
            case unsupportedBitOffset(UInt32)
            
            case missingListEnd
        }
    }
    
    public var debugDescription: String {
        switch self {
        case .int(let int):
            return int.description
        case .double(let double):
            return double.debugDescription
        case .atom(let string):
            return #":"\#(string)""#
        case .string(let string):
            return #""\#(string)""#
        case .ref(let reference):
            return "#Ref"
        case .port(let port):
            return "#Port"
        case .pid(let pid):
            return "#PID"
        case .tuple(let array):
            return "{\(array.map(\.debugDescription).joined(separator: ", "))}"
        case .list(let array):
            return "[\(array.map(\.debugDescription).joined(separator: ", "))]"
        case .binary(let data):
            return String(data: data, encoding: .utf8).map { #""\#($0)""# }
                ?? "#binary<\(data.debugDescription)>"
        case .bitstring(let data):
            return "#Bitstring<\(data.debugDescription)>"
        case .function(let function):
            return "#Function"
        case .map(let dictionary):
            return "%{ \(dictionary.map({ "\($0.key) => \($0.value)" }).joined(separator: ", ")) }"
        }
    }
}

// MARK: TermEncoder

// Based on `JSONEncoder` from `apple/swift-foundation`
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception

/// A type that encodes `Encodable` values into ``erlang/ei_x_buff``.
///
/// Use property wrappers to customize how values are converted to Erlang terms:
/// 
/// - ``TermStringEncoding``
/// - ``TermUnkeyedContainerEncoding``
/// - ``TermKeyedContainerEncoding``
open class TermEncoder {
    open var userInfo: [CodingUserInfoKey: Any] {
        get { options.userInfo }
        set { options.userInfo = newValue }
    }
    
    open var includeVersion: Bool {
        get { options.includeVersion }
        set { options.includeVersion = newValue }
    }
    
    open var stringEncodingStrategy: StringEncodingStrategy {
        get { context.stringEncodingStrategy }
        set { context.stringEncodingStrategy = newValue }
    }
    
    open var unkeyedContainerEncodingStrategy: UnkeyedContainerEncodingStrategy {
        get { context.unkeyedContainerEncodingStrategy }
        set { context.unkeyedContainerEncodingStrategy = newValue }
    }
    
    open var keyedContainerEncodingStrategy: KeyedContainerEncodingStrategy {
        get { context.keyedContainerEncodingStrategy }
        set { context.keyedContainerEncodingStrategy = newValue }
    }
    
    var context: Context
    var options: Options
    
    struct Options {
        var userInfo: [CodingUserInfoKey: Any]
        var includeVersion: Bool
    }
    
    public init() {
        let context = Context()
        self.context = context
        self.options = .init(userInfo: [.termEncoderContext: context], includeVersion: true)
    }
    
    /// Encode `value` to ``erlang/ei_x_buff``.
    open func encode<T: Encodable>(_ value: T) throws -> ei_x_buff {
        let encoder = __TermEncoder(options: self.options, context: self.context, codingPathDepth: 0)
        
        try value.encode(to: encoder)
        var valueBuffer = encoder.storage.popReference().backing.buffer
        
        var buffer = ei_x_buff()
        if includeVersion {
            ei_x_new_with_version(&buffer)
        } else {
            ei_x_new(&buffer)
        }
        ei_x_append(&buffer, &valueBuffer)
        
        return buffer
    }
}

extension CodingUserInfoKey {
    /// A reference to the ``TermEncoder/Context`` for customization.
    public static let termEncoderContext: CodingUserInfoKey = CodingUserInfoKey(rawValue: "$erlang_term_encoder_context")!
}

extension TermEncoder {
    public final class Context {
        public var stringEncodingStrategy: TermEncoder.StringEncodingStrategy = .binary
        public var unkeyedContainerEncodingStrategy: TermEncoder.UnkeyedContainerEncodingStrategy = .list
        public var keyedContainerEncodingStrategy: TermEncoder.KeyedContainerEncodingStrategy = .map
    }
    
    /// The strategy used to encode a ``Swift/String`` to an Erlang term.
    public enum StringEncodingStrategy {
        /// Encodes the string as a binary.
        ///
        /// > A binary is a bitstring where the number of bits is divisible by 8.
        /// > - [Binaries, strings, and charlists](https://hexdocs.pm/elixir/binaries-strings-and-charlists.html)
        case binary
        
        /// Encodes the string as an atom.
        ///
        /// > Atoms are constants whose values are their own name.
        /// >
        /// > [*Atom*](https://hexdocs.pm/elixir/Atom.html)
        case atom
        
        /// Encodes the string as a charlist.
        ///
        /// > A charlist is a list of integers where all the integers are valid code points.
        /// >
        /// > [*Binaries, strings, and charlists*](https://hexdocs.pm/elixir/binaries-strings-and-charlists.html)
        case charlist
    }
    
    /// The strategy used to encode unkeyed containers to an Erlang term.
    public enum UnkeyedContainerEncodingStrategy {
        /// Encodes the container as a list.
        case list
        
        /// Encodes the container as a tuple.
        case tuple
    }
    
    /// The strategy used to encode keyed containers to an Erlang term.
    public enum KeyedContainerEncodingStrategy {
        /// Encodes the container as a map.
        ///
        /// Provide a ``TermEncoder/StringEncodingStrategy`` to specify how keys
        /// should be encoded.
        case map(keyEncodingStrategy: StringEncodingStrategy)
        
        /// Encodes the container as a map with atom keys.
        public static var map: Self { .map(keyEncodingStrategy: .atom) }
        
        /// Encodes the container as a keyword list.
        ///
        /// The key will be encoded as an atom.
        ///
        /// > A keyword list is a list that consists exclusively of two-element tuples.
        /// >
        /// > [*Keyword*](https://hexdocs.pm/elixir/Keyword.html)
        case keywordList
    }
}

/// Customizes the ``TermEncoder/Context/stringEncodingStrategy`` for the
/// wrapped property.
@propertyWrapper
public struct TermStringEncoding: Codable {
    public var wrappedValue: String
    let strategy: TermEncoder.StringEncodingStrategy
    
    public init(wrappedValue: String = "", _ strategy: TermEncoder.StringEncodingStrategy) {
        self.wrappedValue = wrappedValue
        self.strategy = strategy
    }
    
    public init(from decoder: any Decoder) throws {
        self.wrappedValue = try decoder.singleValueContainer().decode(String.self)
        self.strategy = .binary
    }
    
    public func encode(to encoder: any Encoder) throws {
        let context = encoder.userInfo[.termEncoderContext] as! TermEncoder.Context
        let oldStrategy = context.stringEncodingStrategy
        defer {
            context.stringEncodingStrategy = oldStrategy
        }
        context.stringEncodingStrategy = self.strategy
        
        var container = try encoder.singleValueContainer()
        try container.encode(self.wrappedValue)
    }
}

/// Customizes the ``TermEncoder/Context/unkeyedContainerEncodingStrategy`` for
/// the wrapped property.
@propertyWrapper
public struct TermUnkeyedContainerEncoding<Value> {
    public var wrappedValue: Value
    let strategy: TermEncoder.UnkeyedContainerEncodingStrategy
    
    public init(wrappedValue: Value, _ strategy: TermEncoder.UnkeyedContainerEncodingStrategy) {
        self.wrappedValue = wrappedValue
        self.strategy = strategy
    }
}

/// Customizes the ``TermEncoder/Context/keyedContainerEncodingStrategy`` for
/// the wrapped property.
extension TermUnkeyedContainerEncoding: Encodable where Value: Encodable {
    public func encode(to encoder: any Encoder) throws {
        let context = encoder.userInfo[.termEncoderContext] as! TermEncoder.Context
        let oldStrategy = context.unkeyedContainerEncodingStrategy
        defer {
            context.unkeyedContainerEncodingStrategy = oldStrategy
        }
        context.unkeyedContainerEncodingStrategy = self.strategy
        
        var container = try encoder.singleValueContainer()
        try container.encode(self.wrappedValue)
    }
}

extension TermUnkeyedContainerEncoding: Decodable where Value: Decodable {
    public init(from decoder: any Decoder) throws {
        self.wrappedValue = try decoder.singleValueContainer().decode(Value.self)
        self.strategy = .list
    }
}

/// Customizes the ``TermEncoder/Context/keyedContainerEncodingStrategy`` for
/// the wrapped property.
@propertyWrapper
public struct TermKeyedContainerEncoding<Value> {
    public var wrappedValue: Value
    let strategy: TermEncoder.KeyedContainerEncodingStrategy
    
    public init(wrappedValue: Value, _ strategy: TermEncoder.KeyedContainerEncodingStrategy) {
        self.wrappedValue = wrappedValue
        self.strategy = strategy
    }
}

extension TermKeyedContainerEncoding: Encodable where Value: Encodable {
    public func encode(to encoder: any Encoder) throws {
        let context = encoder.userInfo[.termEncoderContext] as! TermEncoder.Context
        let oldStrategy = context.keyedContainerEncodingStrategy
        defer {
            context.keyedContainerEncodingStrategy = oldStrategy
        }
        context.keyedContainerEncodingStrategy = self.strategy
        
        var container = try encoder.singleValueContainer()
        try container.encode(self.wrappedValue)
    }
}

extension TermKeyedContainerEncoding: Decodable where Value: Decodable {
    public init(from decoder: any Decoder) throws {
        self.wrappedValue = try decoder.singleValueContainer().decode(Value.self)
        self.strategy = .map
    }
}

private final class TermReference {
    var backing: Backing
    
    enum Backing {
        case buffer(ei_x_buff)
        case list([TermReference], strategy: TermEncoder.UnkeyedContainerEncodingStrategy)
        case map([String:TermReference], strategy: TermEncoder.KeyedContainerEncodingStrategy)
        
        var buffer: ei_x_buff {
            switch self {
            case let .buffer(buffer):
                return buffer
            case let .list(list, .list) where list.isEmpty:
                var buffer = ei_x_buff()
                ei_x_new(&buffer)
                ei_x_encode_empty_list(&buffer)
                return buffer
            case let .list(list, .list):
                var buffer = ei_x_buff()
                ei_x_new(&buffer)
                ei_x_encode_list_header(&buffer, list.count)
                for element in list {
                    var elementBuffer = element.backing.buffer
                    ei_x_append(&buffer, &elementBuffer)
                }
                ei_x_encode_list_header(&buffer, 0) // tail
                return buffer
            case let .list(list, .tuple):
                var buffer = ei_x_buff()
                ei_x_new(&buffer)
                ei_x_encode_tuple_header(&buffer, list.count)
                for element in list {
                    var elementBuffer = element.backing.buffer
                    ei_x_append(&buffer, &elementBuffer)
                }
                return buffer
            case let .map(map, .map(keyEncodingStrategy)):
                var buffer = ei_x_buff()
                ei_x_new(&buffer)
                ei_x_encode_map_header(&buffer, map.count)
                for (key, value) in map {
                    switch keyEncodingStrategy {
                    case .binary:
                        try Data(key.utf8).withUnsafeBytes { pointer in
                            ei_x_encode_binary(&buffer, pointer.baseAddress!, Int32(pointer.count))
                        }
                    case .atom:
                        ei_x_encode_atom(&buffer, key)
                    case .charlist:
                        ei_x_encode_string(&buffer, strdup(key))
                    }
                    
                    var valueBuffer = value.backing.buffer
                    ei_x_append(&buffer, &valueBuffer)
                }
                return buffer
            case let .map(map, .keywordList):
                var buffer = ei_x_buff()
                ei_x_new(&buffer)
                ei_x_encode_list_header(&buffer, map.count)
                for (key, value) in map {
                    ei_x_encode_tuple_header(&buffer, 2)
                    ei_x_encode_atom(&buffer, key)
                    
                    var valueBuffer = value.backing.buffer
                    ei_x_append(&buffer, &valueBuffer)
                }
                ei_x_encode_list_header(&buffer, 0) // tail
                return buffer
            }
        }
    }
    
    init(_ backing: Backing) {
        self.backing = backing
    }
    
    init(_ makeBuffer: (UnsafeMutablePointer<ei_x_buff>) throws -> ()) rethrows {
        var buffer = ei_x_buff()
        ei_x_new(&buffer)
        try makeBuffer(&buffer)
        self.backing = .buffer(buffer)
    }
    
    @inline(__always)
    var isMap: Bool {
        if case .map = backing {
            return true
        } else {
            return false
        }
    }
    
    @inline(__always)
    var isList: Bool {
        if case .list = backing {
            return true
        } else {
            return false
        }
    }
    
    /// Add a value to an ``Backing/map``.
    @inline(__always)
    func insert(_ value: TermReference, for key: CodingKey) {
        guard case .map(var map, let strategy) = backing else {
            preconditionFailure("Wrong term type")
        }
        map[key.stringValue] = value
        backing = .map(map, strategy: strategy)
    }

    /// Insert a value into an ``Backing/list``.
    @inline(__always)
    func insert(_ value: TermReference, at index: Int) {
        guard case .list(var list, let strategy) = backing else {
            preconditionFailure("Wrong term type")
        }
        list.insert(value, at: index)
        backing = .list(list, strategy: strategy)
    }

    /// Append a value to a ``Backing/list``.
    @inline(__always)
    func insert(_ value: TermReference) {
        guard case .list(var list, let strategy) = backing else {
            preconditionFailure("Wrong term type")
        }
        list.append(value)
        backing = .list(list, strategy: strategy)
    }

    /// `count` from an ``Backing/list`` or ``Backing/map``.
    @inline(__always)
    var count: Int {
        switch backing {
        case let .list(list, _): return list.count
        case let .map(map, _): return map.count
        default: preconditionFailure("Count does not apply to \(self)")
        }
    }

    @inline(__always)
    subscript(_ key: CodingKey) -> TermReference? {
        switch backing {
        case let .map(map, _):
            return map[key.stringValue]
        default:
            preconditionFailure("Wrong underlying term reference type")
        }
    }

    @inline(__always)
    subscript(_ index: Int) -> TermReference {
        switch backing {
        case let .list(list, _):
            return list[index]
        default:
            preconditionFailure("Wrong underlying term reference type")
        }
    }
}

/// The internal `Encoder` used by ``TermEncoder``.
private class __TermEncoder: Encoder {
    var storage: _TermEncodingStorage
    
    var options: TermEncoder.Options
    var context: TermEncoder.Context
    
    var codingPath: [CodingKey]
    
    public var userInfo: [CodingUserInfoKey: Any] {
        self.options.userInfo
    }
    
    public var stringEncodingStrategy: TermEncoder.StringEncodingStrategy {
        self.context.stringEncodingStrategy
    }
    
    public var unkeyedContainerEncodingStrategy: TermEncoder.UnkeyedContainerEncodingStrategy {
        self.context.unkeyedContainerEncodingStrategy
    }
    
    public var keyedContainerEncodingStrategy: TermEncoder.KeyedContainerEncodingStrategy {
        self.context.keyedContainerEncodingStrategy
    }
    
    var codingPathDepth: Int = 0
    
    init(options: TermEncoder.Options, context: TermEncoder.Context, codingPath: [CodingKey] = [], codingPathDepth: Int) {
        self.options = options
        self.context = context
        self.storage = .init()
        self.codingPath = codingPath
        self.codingPathDepth = codingPathDepth
    }
    
    /// Returns whether a new element can be encoded at this coding path.
    ///
    /// `true` if an element has not yet been encoded at this coding path; `false` otherwise.
    var canEncodeNewValue: Bool {
        // Every time a new value gets encoded, the key it's encoded for is pushed onto the coding path (even if it's a nil key from an unkeyed container).
        // At the same time, every time a container is requested, a new value gets pushed onto the storage stack.
        // If there are more values on the storage stack than on the coding path, it means the value is requesting more than one container, which violates the precondition.
        //
        // This means that anytime something that can request a new container goes onto the stack, we MUST push a key onto the coding path.
        // Things which will not request containers do not need to have the coding path extended for them (but it doesn't matter if it is, because they will not reach here).
        return self.storage.count == self.codingPathDepth
    }
    
    public func container<Key>(keyedBy: Key.Type) -> KeyedEncodingContainer<Key> {
        let topRef: TermReference
        if self.canEncodeNewValue {
            topRef = self.storage.pushKeyedContainer(strategy: keyedContainerEncodingStrategy)
        } else {
            guard let ref = self.storage.refs.last, ref.isMap else {
                preconditionFailure(
                    "Attempt to push new keyed encoding container when already previously encoded at this path."
                )
            }
            topRef = ref
        }
        
        let container = _TermKeyedEncodingContainer<Key>(
            referencing: self, codingPath: self.codingPath, wrapping: topRef)
        return KeyedEncodingContainer(container)
    }
    
    public func unkeyedContainer() -> UnkeyedEncodingContainer {
        let topRef: TermReference
        if self.canEncodeNewValue {
            topRef = self.storage.pushUnkeyedContainer(strategy: unkeyedContainerEncodingStrategy)
        } else {
            guard let ref = self.storage.refs.last, ref.isList else {
                preconditionFailure(
                    "Attempt to push new unkeyed encoding container when already previously encoded at this path."
                )
            }
            topRef = ref
        }
        
        return _TermUnkeyedEncodingContainer(
            referencing: self, codingPath: self.codingPath, wrapping: topRef)
    }
    
    public func singleValueContainer() -> SingleValueEncodingContainer {
        self
    }
    
    /// Temporarily modifies the Encoder to use a new `[CodingKey]` path while encoding a nested value.
    ///
    /// The original path/depth is restored after `closure` completes.
    @inline(__always)
    func with<T>(path: [CodingKey]?, perform closure: () throws -> T) rethrows -> T {
        let oldPath = codingPath
        let oldDepth = codingPathDepth
        
        if let path {
            self.codingPath = path
            self.codingPathDepth = path.count
        }
        
        defer {
            if path != nil {
                self.codingPath = oldPath
                self.codingPathDepth = oldDepth
            }
        }
        
        return try closure()
    }
}

extension __TermEncoder {
    @inline(__always) fileprivate func wrap(_ value: Bool, codingPath: [any CodingKey]) throws -> TermReference {
        try TermReference {
            guard ei_x_encode_boolean($0, value ? 1 : 0) == 0
            else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode \(value)")) }
        }
    }
    
    @inline(__always) fileprivate func wrap(_ value: Int, codingPath: [any CodingKey]) throws -> TermReference {
        try TermReference {
            guard ei_x_encode_long($0, value) == 0
            else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode \(value)")) }
        }
    }
    
    @inline(__always) fileprivate func wrap(_ value: Int8, codingPath: [any CodingKey]) throws -> TermReference {
        try wrap(Int(value), codingPath: codingPath)
    }
    
    @inline(__always) fileprivate func wrap(_ value: Int16, codingPath: [any CodingKey]) throws -> TermReference {
        try wrap(Int(value), codingPath: codingPath)
    }
    
    @inline(__always) fileprivate func wrap(_ value: Int32, codingPath: [any CodingKey]) throws -> TermReference {
        try wrap(Int(value), codingPath: codingPath)
    }
    
    @inline(__always) fileprivate func wrap(_ value: Int64, codingPath: [any CodingKey]) throws -> TermReference {
        try TermReference {
            guard ei_x_encode_longlong($0, value) == 0
            else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode \(value)")) }
        }
    }
    
    @inline(__always) fileprivate func wrap(_ value: UInt, codingPath: [any CodingKey]) throws -> TermReference {
        try TermReference {
            guard ei_x_encode_ulong($0, value) == 0
            else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode \(value)")) }
        }
    }
    
    @inline(__always) fileprivate func wrap(_ value: UInt8, codingPath: [any CodingKey]) throws -> TermReference {
        try wrap(UInt(value), codingPath: codingPath)
    }
    
    @inline(__always) fileprivate func wrap(_ value: UInt16, codingPath: [any CodingKey]) throws -> TermReference {
        try wrap(UInt(value), codingPath: codingPath)
    }
    
    @inline(__always) fileprivate func wrap(_ value: UInt32, codingPath: [any CodingKey]) throws -> TermReference {
        try wrap(UInt(value), codingPath: codingPath)
    }
    
    @inline(__always) fileprivate func wrap(_ value: UInt64, codingPath: [any CodingKey]) throws -> TermReference {
        try TermReference {
            guard ei_x_encode_ulonglong($0, value) == 0
            else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode \(value)")) }
        }
    }
    
    @inline(__always) fileprivate func wrap(_ value: String, codingPath: [any CodingKey]) throws -> TermReference {
        try TermReference { buffer in
            switch context.stringEncodingStrategy {
            case .binary:
                try Data(value.utf8).withUnsafeBytes { pointer in
                    guard ei_x_encode_binary(buffer, pointer.baseAddress!, Int32(pointer.count)) == 0
                    else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode \(value)")) }
                }
            case .atom:
                guard ei_x_encode_atom(buffer, value) == 0
                else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode \(value)")) }
            case .charlist:
                guard ei_x_encode_string(buffer, strdup(value)) == 0
                else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode \(value)")) }
            }
        }
    }
    
    @inline(__always) fileprivate func wrap(_ value: Double, codingPath: [any CodingKey]) throws -> TermReference {
        try TermReference {
            guard ei_x_encode_double($0, value) == 0
            else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode \(value)")) }
        }
    }
    
    @inline(__always) fileprivate func wrap(_ value: Float, codingPath: [any CodingKey]) throws -> TermReference {
        try wrap(Double(value), codingPath: codingPath)
    }
    
    fileprivate func wrap(
        _ value: Encodable, for codingPath: [CodingKey],
        _ additionalKey: (some CodingKey)? = AnyCodingKey?.none
    ) throws -> TermReference {
        return try self._wrapGeneric({
            try value.encode(to: $0)
        }, for: codingPath, additionalKey)
        ?? .init(.map([:], strategy: keyedContainerEncodingStrategy))
    }
    
    fileprivate func _wrapGeneric(
        _ encode: (__TermEncoder) throws -> Void, for codingPath: [CodingKey],
        _ additionalKey: (some CodingKey)? = AnyCodingKey?.none
    ) throws -> TermReference? {
        // The value should request a container from the __TermEncoder.
        let depth = self.storage.count
        do {
            try self.with(path: codingPath + (additionalKey.flatMap({ [$0] }) ?? [])) {
                try encode(self)
            }
        } catch {
            // If the value pushed a container before throwing, pop it back off to restore state.
            if self.storage.count > depth {
                let _ = self.storage.popReference()
            }

            throw error
        }

        // The top container should be a new container.
        guard self.storage.count > depth else {
            return nil
        }

        return self.storage.popReference()
    }
}

/// Storage for a ``__TermEncoder``.
private struct _TermEncodingStorage {
    var refs = [TermReference]()
    
    init() {}
    
    var count: Int {
        return self.refs.count
    }
    
    mutating func pushKeyedContainer(strategy: TermEncoder.KeyedContainerEncodingStrategy) -> TermReference {
        let reference = TermReference(.map([:], strategy: strategy))
        self.refs.append(reference)
        return reference
    }
    
    mutating func pushUnkeyedContainer(strategy: TermEncoder.UnkeyedContainerEncodingStrategy) -> TermReference {
        let reference = TermReference(.list([], strategy: strategy))
        self.refs.append(reference)
        return reference
    }
    
    mutating func push(ref: __owned TermReference) {
        self.refs.append(ref)
    }
    
    mutating func popReference() -> TermReference {
        precondition(!self.refs.isEmpty, "Empty reference stack.")
        return self.refs.popLast().unsafelyUnwrapped
    }
}

/// Container for encoding an object.
private struct _TermKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    private let encoder: __TermEncoder

    private let reference: TermReference

    public var codingPath: [CodingKey]

    init(referencing encoder: __TermEncoder, codingPath: [CodingKey], wrapping ref: TermReference) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.reference = ref
    }

    public mutating func encodeNil(forKey key: Key) throws {
        reference.insert(try TermReference {
            guard ei_x_encode_empty_list($0) == 0
            else { throw EncodingError.invalidValue(Optional<Any>.none, EncodingError.Context(codingPath: codingPath + [key], debugDescription: "Failed to encode 'nil'")) }
        }, for: key)
    }
    public mutating func encode(_ value: Bool, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    public mutating func encode(_ value: Int, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    public mutating func encode(_ value: Int8, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    public mutating func encode(_ value: Int16, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    public mutating func encode(_ value: Int32, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    public mutating func encode(_ value: Int64, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    public mutating func encode(_ value: UInt, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    public mutating func encode(_ value: UInt8, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    public mutating func encode(_ value: UInt16, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    public mutating func encode(_ value: UInt32, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    public mutating func encode(_ value: UInt64, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }
    
    public mutating func encode(_ value: String, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }

    public mutating func encode(_ value: Float, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }

    public mutating func encode(_ value: Double, forKey key: Key) throws {
        reference.insert(try encoder.wrap(value, for: codingPath + [key]), for: key)
    }

    public mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        let wrapped = try self.encoder.wrap(value, for: self.encoder.codingPath, key)
        reference.insert(wrapped, for: key)
    }

    public mutating func nestedContainer<NestedKey>(
        keyedBy keyType: NestedKey.Type, forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        let containerKey = key
        let nestedRef: TermReference
        if let existingRef = self.reference[containerKey] {
            precondition(
                existingRef.isMap,
                "Attempt to re-encode into nested KeyedEncodingContainer<\(Key.self)> for key \"\(containerKey)\" is invalid: non-keyed container already encoded for this key"
            )
            nestedRef = existingRef
        } else {
            nestedRef = .init(.map([:], strategy: encoder.keyedContainerEncodingStrategy))
            self.reference.insert(nestedRef, for: containerKey)
        }

        let container = _TermKeyedEncodingContainer<NestedKey>(
            referencing: self.encoder, codingPath: self.codingPath + [key], wrapping: nestedRef)
        return KeyedEncodingContainer(container)
    }

    public mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let containerKey = key
        let nestedRef: TermReference
        if let existingRef = self.reference[containerKey] {
            precondition(
                existingRef.isList,
                "Attempt to re-encode into nested UnkeyedEncodingContainer for key \"\(containerKey)\" is invalid: keyed container/single value already encoded for this key"
            )
            nestedRef = existingRef
        } else {
            nestedRef = .init(.list([], strategy: encoder.unkeyedContainerEncodingStrategy))
            self.reference.insert(nestedRef, for: containerKey)
        }

        return _TermUnkeyedEncodingContainer(
            referencing: self.encoder, codingPath: self.codingPath + [key], wrapping: nestedRef)
    }

    public mutating func superEncoder() -> Encoder {
        fatalError("not supported")
    }

    public mutating func superEncoder(forKey key: Key) -> Encoder {
        fatalError("not supported")
    }
}

/// Container for encoding an array.
private struct _TermUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    private let encoder: __TermEncoder

    private let reference: TermReference

    var codingPath: [CodingKey]

    public var count: Int {
        self.reference.count
    }

    init(referencing encoder: __TermEncoder, codingPath: [CodingKey], wrapping ref: TermReference) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.reference = ref
    }

    public mutating func encodeNil() throws {
        self.reference.insert(try TermReference {
            guard ei_x_encode_empty_list($0) == 0
            else { throw EncodingError.invalidValue(Optional<Any>.none, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode 'nil'")) }
        })
    }
    public mutating func encode(_ value: Bool) throws {
        self.reference.insert(try TermReference {
            guard ei_x_encode_boolean($0, value ? 1 : 0) == 0
            else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode '\(value)'")) }
        })
    }
    public mutating func encode(_ value: Int) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: Int8) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: Int16) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: Int32) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: Int64) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: UInt) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: UInt8) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: UInt16) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: UInt32) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: UInt64) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: String) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: Float) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }
    public mutating func encode(_ value: Double) throws {
        self.reference.insert(try encoder.wrap(value, for: codingPath))
    }

    public mutating func encode<T: Encodable>(_ value: T) throws {
        let wrapped = try self.encoder.wrap(
            value, for: self.encoder.codingPath,
            AnyCodingKey(stringValue: "Index \(self.count)", intValue: self.count))
        self.reference.insert(wrapped)
    }

    public mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type)
        -> KeyedEncodingContainer<NestedKey>
    {
        let key = AnyCodingKey(index: self.count)
        let nestedRef = TermReference(.map([:], strategy: encoder.keyedContainerEncodingStrategy))
        self.reference.insert(nestedRef)
        let container = _TermKeyedEncodingContainer<NestedKey>(
            referencing: self.encoder, codingPath: self.codingPath + [key], wrapping: nestedRef)
        return KeyedEncodingContainer(container)
    }

    public mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let key = AnyCodingKey(index: self.count)
        let nestedRef = TermReference(.list([], strategy: encoder.unkeyedContainerEncodingStrategy))
        self.reference.insert(nestedRef)
        return _TermUnkeyedEncodingContainer(
            referencing: self.encoder, codingPath: self.codingPath + [key], wrapping: nestedRef)
    }

    public mutating func superEncoder() -> Encoder {
        fatalError("not supported")
    }
}

/// Container for encoding a single value.
extension __TermEncoder: SingleValueEncodingContainer {
    private func assertCanEncodeNewValue() {
        precondition(
            self.canEncodeNewValue,
            "Attempt to encode value through single value container when previously value already encoded."
        )
    }
    
    public func encodeNil() throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try .init {
            guard ei_x_encode_empty_list($0) == 0
            else { throw EncodingError.invalidValue(Optional<Any>.none, EncodingError.Context(codingPath: codingPath, debugDescription: "Failed to encode 'nil'")) }
        })
    }
    
    public func encode(_ value: Bool) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: Int) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: Int8) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: Int16) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: Int32) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: Int64) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: UInt) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: UInt8) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: UInt16) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: UInt32) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: UInt64) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: String) throws {
        assertCanEncodeNewValue()
        self.storage.push(ref: try wrap(value, codingPath: codingPath))
    }
    
    public func encode(_ value: Float) throws {
        assertCanEncodeNewValue()
        let wrapped = try self.wrap(value, codingPath: codingPath)
        self.storage.push(ref: wrapped)
    }
    
    public func encode(_ value: Double) throws {
        assertCanEncodeNewValue()
        let wrapped = try self.wrap(value, codingPath: codingPath)
        self.storage.push(ref: wrapped)
    }
    
    public func encode<T: Encodable>(_ value: T) throws {
        assertCanEncodeNewValue()
        try self.storage.push(ref: self.wrap(value, for: self.codingPath))
    }
}

// MARK: TermDecoder

/// A type that decodes `Term` to a `Decodable` type.
open class TermDecoder {
    open var userInfo: [CodingUserInfoKey: Any] {
        get { options.userInfo }
        set { options.userInfo = newValue }
    }
    
    var options = Options()

    public struct Options {
        public var userInfo: [CodingUserInfoKey: Any] = [:]
        
        public init() {}
        
        public func userInfo(_ userInfo: [CodingUserInfoKey: Any]) -> Self {
            var copy = self
            copy.userInfo = userInfo
            return copy
        }
    }

    public init() {}

    open func decode<T: Decodable>(_ type: T.Type, from buffer: ei_x_buff, startIndex: Int32 = 0) throws -> T {
        let decoder = __TermDecoder(
            userInfo: userInfo,
            from: buffer,
            codingPath: [],
            options: self.options,
            startIndex: startIndex
        )
        return try type.init(from: decoder)
    }
}

final class __TermDecoder: Decoder {
    var buffer: ei_x_buff
    
    var index: Int32

    let userInfo: [CodingUserInfoKey: Any]
    let options: TermDecoder.Options

    public var codingPath: [CodingKey]

    init(
        userInfo: [CodingUserInfoKey: Any],
        from buffer: ei_x_buff,
        codingPath: [CodingKey],
        options: TermDecoder.Options,
        startIndex: Int32 = 0
    ) {
        self.userInfo = userInfo
        self.codingPath = codingPath
        self.buffer = buffer
        self.options = options
        self.index = startIndex
        var version: Int32 = 0
        ei_decode_version(buffer.buff, &index, &version)
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key>
    where Key: CodingKey {
        var arity: Int32 = 0
        guard ei_decode_map_header(buffer.buff, &index, &arity) == 0
        else {
            throw DecodingError.makeTypeMismatchError(
                type: [AnyHashable:Any].self,
                for: codingPath,
                in: self
            )
        }
        
        return KeyedDecodingContainer(
            try KeyedContainer<Key>(decoder: self, codingPath: codingPath, arity: arity)
        )
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        var type: UInt32 = 0
        var size: Int32 = 0
        guard ei_get_type(buffer.buff, &index, &type, &size) == 0
        else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Unable to get type of term")) }
        
        let isTuple: Bool
        switch Character(UnicodeScalar(type)!) {
        case "h", "i": // tuple
            isTuple = true
        case "l", "j": // list
            isTuple = false
        default:
            throw DecodingError.makeTypeMismatchError(
                type: [Any].self,
                for: codingPath,
                in: self
            )
        }
        
        return try UnkeyedContainer(decoder: self, codingPath: codingPath, isTuple: isTuple)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        self
    }
}

extension __TermDecoder: SingleValueDecodingContainer {
    func decodeNil() -> Bool {
        var arity: Int32 = 0
        
        guard ei_decode_list_header(buffer.buff, &index, &arity) == 0,
              arity == 0
        else { return false }
        
        return true
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        var bool: Int32 = 0
        guard ei_decode_boolean(buffer.buff, &index, &bool) == 0
        else { throw DecodingError.makeTypeMismatchError(type: type, for: codingPath, in: self) }
        return bool == 1
    }

    func decode(_ type: String.Type) throws -> String {
        var _type: UInt32 = 0
        var size: Int32 = 0
        guard ei_get_type(buffer.buff, &index, &_type, &size) == 0
        else { throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Failed to get size of binary")) }
        
        switch Character(UnicodeScalar(_type)!) {
        case "d", "s", "v": // atom
            var atom: [CChar] = [CChar](repeating: 0, count: Int(MAXATOMLEN))
            guard ei_decode_atom(buffer.buff, &index, &atom) == 0
            else { throw DecodingError.makeTypeMismatchError(type: type, for: codingPath, in: self) }
            return String(cString: atom)
        case "m": // binary
            var binary: UnsafeMutableRawPointer = .allocate(byteCount: Int(size), alignment: 0)
            var length: Int = 0
            guard ei_decode_binary(buffer.buff, &index, binary, &length) == 0
            else { throw DecodingError.makeTypeMismatchError(type: type, for: codingPath, in: self) }
            
            guard let string = String(data: Data(bytes: binary, count: length), encoding: .utf8)
            else { throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Failed to decode binary to String")) }
            return string
        case "k": // string
            var string: UnsafeMutablePointer<CChar> = .allocate(capacity: Int(size) + 1)
            defer { string.deallocate() }
            guard ei_decode_string(buffer.buff, &index, string) == 0
            else { throw DecodingError.makeTypeMismatchError(type: type, for: codingPath, in: self) }
            return String(cString: string)
        default:
            throw DecodingError.makeTypeMismatchError(type: type, for: codingPath, in: self)
        }
    }

    func decode(_ type: Double.Type) throws -> Double {
        var double: Double = 0
        
        guard ei_decode_double(buffer.buff, &index, &double) == 0
        else { throw DecodingError.makeTypeMismatchError(type: type, for: codingPath, in: self) }
        
        return double
    }

    func decode(_ type: Float.Type) throws -> Float {
        return Float(try decode(Double.self))
    }

    func decode(_ type: Int.Type) throws -> Int {
        var int: Int = 0
        
        guard ei_decode_long(buffer.buff, &index, &int) == 0
        else { throw DecodingError.makeTypeMismatchError(type: type, for: codingPath, in: self) }
        
        return int
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        Int8(try decode(Int.self))
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        Int16(try decode(Int.self))
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        Int32(try decode(Int.self))
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        var int: Int64 = 0
        
        guard ei_decode_longlong(buffer.buff, &index, &int) == 0
        else { throw DecodingError.makeTypeMismatchError(type: type, for: codingPath, in: self) }
        
        return int
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        var int: UInt = 0
        
        guard ei_decode_ulong(buffer.buff, &index, &int) == 0
        else { throw DecodingError.makeTypeMismatchError(type: type, for: codingPath, in: self) }
        
        return int
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        UInt8(try decode(UInt.self))
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        UInt16(try decode(UInt.self))
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        UInt32(try decode(UInt.self))
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        var int: UInt64 = 0
        
        guard ei_decode_ulonglong(buffer.buff, &index, &int) == 0
        else { throw DecodingError.makeTypeMismatchError(type: type, for: codingPath, in: self) }
        
        return int
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        try type.init(from: self)
    }
}

extension __TermDecoder {
    struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let decoder: __TermDecoder
        
        /// The index that starts each value.
        var valueStartIndices = [String:Int32]()
        
        var allKeys: [Key] {
            valueStartIndices.keys.compactMap(Key.init(stringValue:))
        }
        
        var codingPath: [any CodingKey]

        init(
            decoder: __TermDecoder,
            codingPath: [any CodingKey],
            arity: Int32
        ) throws {
            self.decoder = decoder
            self.codingPath = codingPath
            
            // get all of the keys, skipping the values
            for elementIndex in 0..<arity {
                let currentCodingPath = codingPath + [AnyCodingKey(intValue: Int(elementIndex))]
                
                // decode the key as an atom, string, or binary
                var type: UInt32 = 0
                var size: Int32 = 0
                guard ei_get_type(decoder.buffer.buff, &decoder.index, &type, &size) == 0
                else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(
                        codingPath: currentCodingPath,
                        debugDescription: "Failed to get type of key"
                    ))
                }
                
                switch Character(UnicodeScalar(type)!) {
                case "d", "s", "v": // atom
                    var atom: [CChar] = [CChar](repeating: 0, count: Int(MAXATOMLEN))
                    guard ei_decode_atom(decoder.buffer.buff, &decoder.index, &atom) == 0
                    else {
                        throw DecodingError.typeMismatch(
                            String.self,
                            .init(
                                codingPath: currentCodingPath,
                                debugDescription: "Expected atom key in map"
                            )
                        )
                    }
                    valueStartIndices[String(cString: atom)] = decoder.index
                case "k": // string
                    var string: UnsafeMutablePointer<CChar> = .allocate(capacity: Int(size) + 1)
                    defer { string.deallocate() }
                    guard ei_decode_string(decoder.buffer.buff, &decoder.index, string) == 0
                    else {
                        throw DecodingError.typeMismatch(
                            String.self,
                            .init(
                                codingPath: currentCodingPath,
                                debugDescription: "Expected string key in map"
                            )
                        )
                    }
                    valueStartIndices[String(cString: string)] = decoder.index
                case "m": // binary
                    var binary: UnsafeMutableRawPointer = .allocate(byteCount: Int(size), alignment: 0)
                    var length: Int = 0
                    guard ei_decode_binary(decoder.buffer.buff, &decoder.index, binary, &length) == 0,
                          let key = String(data: Data(bytes: binary, count: length), encoding: .utf8)
                    else {
                        throw DecodingError.typeMismatch(
                            String.self,
                            .init(
                                codingPath: currentCodingPath,
                                debugDescription: "Expected binary key in map"
                            )
                        )
                    }
                    valueStartIndices[key] = decoder.index
                default:
                    throw DecodingError.typeMismatch(
                        String.self,
                        .init(
                            codingPath: currentCodingPath,
                            debugDescription: "Expected atom, string, or binary key in map"
                        )
                    )
                }
                
                // skip the value
                ei_skip_term(decoder.buffer.buff, &decoder.index)
            }
        }

        func contains(_ key: Key) -> Bool {
            return true
        }
        
        func withIndex<Result>(forKey key: Key, _ block: (__TermDecoder) throws -> Result) throws -> Result {
            let originalIndex = decoder.index
            let originalCodingPath = decoder.codingPath
            
            defer {
                decoder.index = originalIndex
                decoder.codingPath = originalCodingPath
            }
            
            guard let index = valueStartIndices[key.stringValue]
            else {
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key '\(key)' not found in map"))
            }
            decoder.index = index
            decoder.codingPath = codingPath + [key]
            
            return try block(decoder)
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            guard valueStartIndices.keys.contains(key.stringValue)
            else { return true }
            return try withIndex(forKey: key) {
                $0.decodeNil()
            }
        }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: String.Type, forKey key: Key) throws -> String {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
            try withIndex(forKey: key) {
                try $0.decode(type)
            }
        }

        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws
            -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
        {
            try withIndex(forKey: key) {
                $0.codingPath.append(key)
                return try $0.container(keyedBy: type)
            }
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
            try withIndex(forKey: key) {
                $0.codingPath.append(key)
                return try $0.unkeyedContainer()
            }
        }

        func superDecoder() throws -> any Decoder {
            fatalError("not supported")
        }

        func superDecoder(forKey key: Key) throws -> any Decoder {
            fatalError("not supported")
        }
    }
}

extension __TermDecoder {
    struct UnkeyedContainer: UnkeyedDecodingContainer {
        
        let decoder: __TermDecoder
        
        let isTuple: Bool

        let count: Int?
        var currentIndex: Int = 0
        var isAtEnd: Bool {
            self.currentIndex >= self.count!
        }
        var peekedValue: Any?
        
        var valueStartIndices: [Int32]

        var codingPath: [any CodingKey]
        var currentCodingPath: [any CodingKey] {
            codingPath + [AnyCodingKey(index: currentIndex)]
        }
        
        func with<T>(index: Int32, _ block: (__TermDecoder) throws -> T) rethrows -> T {
            let originalIndex = decoder.index
            let originalCodingPath = decoder.codingPath
            
            defer {
                decoder.index = originalIndex
                decoder.codingPath = originalCodingPath
            }
            
            decoder.index = index
            decoder.codingPath = currentCodingPath
            
            return try block(decoder)
        }

        init(
            decoder: __TermDecoder,
            codingPath: [CodingKey],
            isTuple: Bool
        ) throws {
            self.decoder = decoder
            self.isTuple = isTuple
            
            var arity: Int32 = 0
            if isTuple {
                guard ei_decode_tuple_header(decoder.buffer.buff, &decoder.index, &arity) == 0
                else {
                    throw DecodingError.makeTypeMismatchError(type: [Any].self, for: codingPath, in: decoder)
                }
            } else {
                guard ei_decode_list_header(decoder.buffer.buff, &decoder.index, &arity) == 0
                else {
                    throw DecodingError.makeTypeMismatchError(type: [Any].self, for: codingPath, in: decoder)
                }
            }
            self.count = Int(arity)
            
            self.codingPath = codingPath
            
            // find the start index of each element and skip to the end of the list
            self.valueStartIndices = []
            for _ in 0..<arity {
                valueStartIndices.append(decoder.index)
                ei_skip_term(decoder.buffer.buff, &decoder.index)
            }
            if !isTuple && arity > 0 {
                // empty list header at the end
                var arity: Int32 = 0
                guard ei_decode_list_header(decoder.buffer.buff, &decoder.index, &arity) == 0,
                      arity == 0
                else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: currentCodingPath, debugDescription: "Missing tail list header")) }
            }
        }

        @inline(__always)
        mutating func peek<T>(_ type: T.Type) throws -> T where T: Decodable {
            if let value = peekedValue as? T {
                return value
            }
            
            guard !isAtEnd
            else {
                var message = "Unkeyed container is at end."
                if T.self == UnkeyedContainer.self {
                    message = "Cannot get nested unkeyed container -- unkeyed container is at end."
                }
                if T.self == Decoder.self {
                    message = "Cannot get superDecoder() -- unkeyed container is at end."
                }

                throw DecodingError.valueNotFound(
                    type,
                    .init(
                        codingPath: codingPath,
                        debugDescription: message
                    )
                )
            }
            
            return try with(index: valueStartIndices[currentIndex]) {
                let nextValue = try $0.decode(T.self)
                peekedValue = nextValue
                return nextValue
            }
        }

        mutating func advance() throws {
            currentIndex += 1
            peekedValue = nil
        }

        mutating func decodeNil() throws -> Bool {
            let value = try self.peek(Never.self)
            return true
        }

        mutating func decode(_ type: Bool.Type) throws -> Bool {
            let value = try peek(type)
            try advance()
            return value
        }

        mutating func decode(_ type: String.Type) throws -> String {
            let value = try peek(type)
            try advance()
            return value
        }

        mutating func decode(_ type: Double.Type) throws -> Double {
            let value = try peek(type)
            try advance()
            return value
        }

        mutating func decode(_ type: Float.Type) throws -> Float {
            let value = try peek(type)
            try advance()
            return value
        }

        mutating func decode(_ type: Int.Type) throws -> Int {
            let value = try peek(type)
            try advance()
            return value
        }

        mutating func decode(_ type: Int8.Type) throws -> Int8 {
            return try type.init(decode(Int.self))
        }

        mutating func decode(_ type: Int16.Type) throws -> Int16 {
            return try type.init(decode(Int.self))
        }

        mutating func decode(_ type: Int32.Type) throws -> Int32 {
            return try type.init(decode(Int.self))
        }

        mutating func decode(_ type: Int64.Type) throws -> Int64 {
            return try type.init(decode(Int.self))
        }

        mutating func decode(_ type: UInt.Type) throws -> UInt {
            let value = try peek(type)
            try advance()
            return value
        }

        mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
            return try type.init(decode(UInt.self))
        }

        mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
            return try type.init(decode(UInt.self))
        }

        mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
            return try type.init(decode(UInt.self))
        }

        mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
            return try type.init(decode(UInt.self))
        }

        mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
            let value = try peek(type)
            try advance()
            return value
        }

        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
            -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
        {
            let container = try with(index: valueStartIndices[currentIndex]) {
                try $0.container(keyedBy: type)
            }
            try advance()
            return container
        }

        mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
            let container = try with(index: valueStartIndices[currentIndex]) {
                try $0.unkeyedContainer()
            }
            try advance()
            return container
        }

        mutating func superDecoder() throws -> any Decoder {
            fatalError("not supported")
        }
    }
}

extension DecodingError {
    fileprivate static func makeTypeMismatchError(
        type expectedType: Any.Type, for path: [CodingKey], in decoder: __TermDecoder
    ) -> DecodingError {
        var type: UInt32 = 0
        var size: Int32 = 0
        ei_get_type(decoder.buffer.buff, &decoder.index, &type, &size)
        
        let typeName = switch Character(UnicodeScalar(type)!) {
        case "a", "b": // integer
            "integer"
        case "c", "F": //  float
            "float"
        case "d", "s", "v": // atom
            "atom"
        case "e", "r", "Z": // ref
            "ref"
        case "f", "Y", "x": // port
            "port"
        case "g", "X": // pid
            "pid"
        case "h", "i": // tuple
            "tuple"
        case "k": // string
            "string"
        case "l": // list
            "list"
        case "j": // empty list
            "empty list"
        case "m": // binary
            "binary"
        case "M": // bit binary
            "bit binary"
        case "p", "u", "q": // function
            "function"
        case "t": // map
            "map"
        case let type:
            String(type)
        }
        
        return DecodingError.typeMismatch(
            expectedType,
            .init(
                codingPath: path,
                debugDescription: "Expected to decode \(expectedType) but found \(typeName) instead."
            )
        )
    }
}

/// A type-erased ``Swift/CodingKey``.
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init(stringValue: String, intValue: Int?) {
        self.stringValue = stringValue
        self.intValue = intValue
    }

    init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }
}
