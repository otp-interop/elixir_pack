import erlang

extension ErlangNode.Connection {
    /// Makes an RPC call with a ``Term`` result type and ``Term``
    /// arguments.
    ///
    /// > Elixir modules must be prefixed with `Elixir.`
    /// >
    /// > By default, the ``module`` argument will refer to an Erlang module.
    public func rpc(
        _ module: String,
        _ function: String,
        _ arguments: [Term]
    ) async throws -> Term {
        let stream = self.messageBuffers()
        
        try await self.sendRPC(module, function, arguments)
        
        for try await message in stream { // find the :rex message
            let message = try message.get()
            
            var index: Int32 = 0
            var arity: Int32 = 0
            var atom: [CChar] = [CChar](repeating: 0, count: Int(MAXATOMLEN))
            
            var version: Int32 = 0
            message.decode(version: &version, index: &index)
            
            message.decode(tupleHeader: &arity, index: &index)
            
            guard arity > 0,
                  message.decode(atom: &atom, index: &index),
                  String(cString: atom, encoding: .utf8) == "rex"
            else { continue }
            
            return try Term(from: message)
        }
        
        throw RPCError.noResponse
    }
    
    public func rpc<each Result: Decodable & Sendable>(
        _ module: String,
        _ function: String,
        _ arguments: [Term]
    ) async throws -> (repeat each Result) {
        let stream = self.messageBuffers()
        
        try await self.sendRPC(module, function, arguments)
        
        for try await message in stream { // find the :rex message
            let message = try message.get()
            
            var index: Int32 = 0
            var arity: Int32 = 0
            var atom: [CChar] = [CChar](repeating: 0, count: Int(MAXATOMLEN))
            
            var version: Int32 = 0
            message.decode(version: &version, index: &index)
            
            message.decode(tupleHeader: &arity, index: &index)
            
            guard arity > 0,
                  message.decode(atom: &atom, index: &index),
                  String(cString: atom, encoding: .utf8) == "rex"
            else { continue }
            
            return try TermDecoder().decode(
                RPCResult<repeat each Result>.self,
                from: message,
                startIndex: index
            ).value
        }
        
        throw RPCError.noResponse
    }
    
    /// Makes an RPC call with a ``Swift/Decodable`` result type and
    /// ``Swift/Encodable`` arguments.
    ///
    /// You can pass any `Encodable` type as an argument, and receive any number of
    /// ``Decodable`` types as a response.
    ///
    /// ```swift
    /// struct Version: Decodable {
    ///     let major: Int
    ///     let minor: Int
    ///     let patch: Int
    ///     let pre: [String]
    /// }
    ///
    /// let version: Version = connection.rpc("Elixir.Version", "parse", ["2.0.1-alpha1"])
    /// ```
    ///
    /// Assign the result to a tuple to decode multiple values.
    ///
    /// ```swift
    /// // from Elixir: {:ok, "John Doe", 36}
    /// let name: String, age: Int
    /// (name, age) = try await connection.rpc("Elixir.User", "get", [0])
    /// ```
    ///
    /// > Elixir modules must be prefixed with `Elixir.`
    /// >
    /// > By default, the ``module`` argument will refer to an Erlang module.
    public func rpc<each Result: Decodable & Sendable>(
        _ module: String,
        _ function: String,
        _ arguments: [any (Encodable & Sendable)]
    ) async throws -> (repeat each Result) {
        let stream = self.messageBuffers()
        
        try await self.sendRPC(module, function, arguments)
        
        for try await message in stream { // find the :rex message
            let message = try message.get()
            
            var index: Int32 = 0
            var arity: Int32 = 0
            var atom: [CChar] = [CChar](repeating: 0, count: Int(MAXATOMLEN))
            
            var version: Int32 = 0
            message.decode(version: &version, index: &index)
            
            message.decode(tupleHeader: &arity, index: &index)
            
            guard arity > 0,
                  message.decode(atom: &atom, index: &index),
                  String(cString: atom, encoding: .utf8) == "rex"
            else { continue }
            
            return try TermDecoder().decode(
                RPCResult<repeat each Result>.self,
                from: message,
                startIndex: index
            ).value
        }
        
        throw RPCError.noResponse
    }
    
    private func sendRPC(
        _ module: String,
        _ function: String,
        _ arguments: [Term]
    ) throws {
        var args = ErlangTermBuffer()
        args.new()
        
        try Term.list(arguments).encode(to: &args, initializeBuffer: false)
        
        var result = ErlangTermBuffer()
        result.new()
        
        guard ei_rpc_to(
            &node.node,
            fileDescriptor,
            strdup(module),
            strdup(function),
            args.buff,
            args.index
        ) == 0
        else { throw RPCError.sendFailed }
    }
    
    private func sendRPC(
        _ module: String,
        _ function: String,
        _ arguments: [any (Encodable & Sendable)]
    ) throws {
        let encoder = TermEncoder()
        encoder.options.includeVersion = false
        let args = try encoder.encode(
            arguments.map(RPCArgument.init(item:))
        )
        
        var result = ErlangTermBuffer()
        result.new()
        
        guard ei_rpc_to(
            &node.node,
            fileDescriptor,
            strdup(module),
            strdup(function),
            args.buff,
            args.index
        ) == 0
        else { throw RPCError.sendFailed }
    }
    
    private enum RPCStatus: String, Decodable {
        case ok
        case badrpc
    }
    
    private struct RPCArgument: Encodable {
        let item: any Encodable
        
        func encode(to encoder: any Encoder) throws {
            var container = try encoder.singleValueContainer()
            try container.encode(item)
        }
    }
    
    private struct RPCResult<each Value: Decodable>: Decodable {
        let status: RPCStatus
        let value: (repeat each Value)
        
        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            self.status = try container.decode(RPCStatus.self)
            switch self.status {
            case .ok:
                self.value = (
                    repeat try container.decode((each Value).self)
                )
            case .badrpc:
                throw RPCError.badrpc
            }
        }
    }
    
    enum RPCError: Error {
        case badrpc
        case noResponse
        case sendFailed
    }
}

/// DSL for using `:rpc`.
///
/// Access modules from your Elixir application and call functions on them by
/// passing the ``ErlangNode/Connection``.
///
/// ```swift
/// try await Elixir.IO.puts(connection, "Hello, world!")
/// ```
///
/// You can pass any `Encodable` type as an argument, and receive any number of
/// ``Decodable`` types as a response.
///
/// ```swift
/// struct Version: Decodable {
///     let major: Int
///     let minor: Int
///     let patch: Int
///     let pre: [String]
/// }
///
/// let version: Version = try await Elixir.Version.parse(connection, "2.0.1-alpha1")
/// ```
///
/// See ``TermEncoder`` for more details on customizing encoding.
///
/// Assign the result to a tuple to decode multiple values.
///
/// ```swift
/// // from Elixir: {:ok, "John Doe", 36}
/// let name: String, age: Int
/// (name, age) = try await Elixir.User.get(connection, 0)
/// ```
@dynamicMemberLookup
public enum Elixir {
    public static subscript(dynamicMember memberName: String) -> Module {
        Module(lhs: "Elixir", rhs: memberName)
    }
    
    @dynamicMemberLookup
    @dynamicCallable
    public struct Module {
        let lhs: String
        let rhs: String
        
        public subscript(dynamicMember memberName: String) -> Module {
            Module(lhs: "\(lhs).\(rhs)", rhs: memberName)
        }
        
        public func dynamicallyCall<each Result: Decodable & Sendable>(
            withArguments arguments: [any Sendable]
        ) async throws -> (repeat each Result) {
            guard let connection = arguments.first as? ErlangNode.Connection
            else { throw RPCError.missingConnection }
            let arguments = arguments
                .dropFirst()
            if arguments.allSatisfy({ $0 is Term }) {
                return try await connection.rpc(
                    lhs,
                    rhs,
                    arguments.map { $0 as! Term }
                )
            } else {
                return try await connection.rpc(
                    lhs,
                    rhs,
                    arguments
                        .map({
                            guard let encodable = $0 as? any Encodable
                            else { throw RPCError.invalidArgument($0) }
                            return encodable as! (any (Encodable & Sendable))
                        })
                )
            }
        }
        
        public func dynamicallyCall(
            withArguments arguments: [any Sendable]
        ) async throws -> Term {
            guard let connection = arguments.first as? ErlangNode.Connection
            else { throw RPCError.missingConnection }
            return try await connection.rpc(
                lhs,
                rhs,
                arguments
                    .dropFirst()
                    .compactMap({
                        guard let term = $0 as? Term
                        else { throw RPCError.invalidArgument($0) }
                        return term
                    })
            )
        }
        
        enum RPCError: Error {
            case missingConnection
            case invalidArgument(any Sendable)
        }
    }
}
