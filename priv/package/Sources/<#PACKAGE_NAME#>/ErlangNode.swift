import Observation
import Foundation
import Combine
import erlang

/// A distributed Erlang node.
///
/// Create a node and connect it your application.
///
/// ```swift
/// let node = try ErlangNode(name: "my_node", cookie: cookie)
/// let connection = try await node.connect(
///     to: "server_node",
///     as: "my_node" // local process name
/// )
/// ```
///
/// - Note: The ``cookie`` value must match on this node and the remote node.
///
/// See ``Connection`` for more information on communicating between nodes.
public actor ErlangNode {
    private var node = CNode()
    
    fileprivate struct CNode: @unchecked Sendable {
        var node = ei_cnode()
    }
    
    /// A connection between an ``ErlangNode`` and another node.
    ///
    /// You don't create this type directly. Instead, establish a connection
    /// with ``ErlangNode/connect(to:as:)``.
    ///
    /// # Messaging
    ///
    /// Use ``send(_:to:)-6wpa5`` to send a message to a process on a remote node.
    ///
    /// ```swift
    /// try await connection.send("Hello, world!", to: "server_process")
    /// ```
    ///
    /// You can receive messages from a remote node with ``receive()``.
    ///
    /// ```swift
    /// let message: Message? = try await connection.receive()
    /// ```
    ///
    /// If you do not have a ``Swift/Decodable`` type defined for all possible
    /// messages, use ``receive()-6qhz3`` to accept a generic ``Term``.
    ///
    /// ```swift
    /// let message: Term? = try await connection.receive()
    /// ```
    ///
    /// You can setup a loop to receive messages. This will also ensure that
    /// your application responds to the tick message.
    ///
    /// ```swift
    /// Task {
    ///     while true {
    ///         guard let message: Message = try await connection.receive()
    ///         else { continue }
    ///         // handle message
    ///     }
    /// }
    /// ```
    ///
    /// # RPC
    ///
    /// Use the ``Elixir`` DSL to call functions on the remote node.
    ///
    /// ```swift
    /// try await Elixir.IO.puts(connection, "Hello, world!")
    /// ```
    ///
    /// See ``Elixir`` for more information on the DSL.
    ///
    /// Use `:rpc` manually with ``rpc(_:_:_:)``.
    ///
    /// ```swift
    /// connection.rpc("Elixir.IO", "puts", ["Hello, world!"])
    /// ```
    public actor Connection: Sendable {
        let fileDescriptor: Int32
        private var node: CNode
        
        let termDecoder = TermDecoder()
        
        fileprivate init(
            fileDescriptor: Int32,
            node: CNode
        ) {
            self.fileDescriptor = fileDescriptor
            self.node = node
        }
        
        /// Send a ``Term`` to a named process on a remote node.
        public func send(
            _ message: Term,
            to process: String
        ) throws {
            let buffer = try Term.tuple([
                .pid(.init(pid: ei_self(&node.node).pointee)),
                message
            ]).makeBuffer()
            
            let status = ei_reg_send(
                &node.node,
                fileDescriptor,
                strdup(process),
                buffer.buff,
                buffer.index
            )
            
            guard status >= 0
            else { throw ErlangNodeError.failedToSend }
        }
        
        /// Send any  ``Swift/Encodable`` type to a named process on a remote
        /// node.
        public func send(
            _ message: some Encodable,
            to process: String
        ) throws {
            var buffer = ei_x_buff()
            ei_x_new_with_version(&buffer)
            
            ei_x_encode_tuple_header(&buffer, 2)
            ei_x_encode_pid(&buffer, ei_self(&node.node))
            
            let encoder = TermEncoder()
            encoder.includeVersion = false
            var messageBuffer = try encoder.encode(message)
            ei_x_append(&buffer, &messageBuffer)
            
            let status = ei_reg_send(
                &node.node,
                fileDescriptor,
                strdup(process),
                buffer.buff,
                buffer.index
            )
            
            guard status >= 0
            else { throw ErlangNodeError.failedToSend }
        }
        
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
            var args = ei_x_buff()
            ei_x_new(&args)
            
            try Term.list(arguments).encode(to: &args, initializeBuffer: false)
            
            var result = ei_x_buff()
            ei_x_new(&result)
            
            guard ei_rpc(
                &node.node,
                fileDescriptor,
                strdup(module),
                strdup(function),
                args.buff,
                args.index,
                &result
            ) == 0
            else { throw ErlangNodeError.rpcFailed }
            
            return try Term(from: &result)
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
        public func rpc<each Result: Decodable>(
            _ module: String,
            _ function: String,
            _ arguments: [any Encodable]
        ) async throws -> (repeat each Result) {
            let encoder = TermEncoder()
            encoder.options.includeVersion = false
            let args = try encoder.encode(
                arguments.map(RPCArgument.init(item:))
            )
            
            var result = ei_x_buff()
            ei_x_new(&result)
            
            guard ei_rpc(
                &node.node,
                fileDescriptor,
                strdup(module),
                strdup(function),
                args.buff,
                args.index,
                &result
            ) == 0
            else { throw ErlangNodeError.rpcFailed }
            
            return try termDecoder.decode(
                RPCResult<repeat each Result>.self,
                from: result
            ).value
        }
        
        /// Receives one message from a remote node, or `nil` if there are no
        /// messages to receive.
        public func receive() throws -> Term? {
            let fileDescriptor = self.fileDescriptor
            
            var message = erlang_msg()
            var buffer = ei_x_buff()
            ei_x_new(&buffer)
            
            switch ei_xreceive_msg_tmo(fileDescriptor, &message, &buffer, 1) {
            case ERL_TICK:
                return nil
            case ERL_ERROR:
                return nil
            default:
                return try Term(from: &buffer)
            }
        }
        
        /// Receives one ``Swift/Decodable`` message from a remote node, or
        /// `nil` if there are no messages to receive.
        public func receive<Result: Decodable>() throws -> Result? {
            let fileDescriptor = self.fileDescriptor
            
            var message = erlang_msg()
            var buffer = ei_x_buff()
            ei_x_new(&buffer)
            
            switch ei_xreceive_msg_tmo(fileDescriptor, &message, &buffer, 1) {
            case ERL_TICK:
                return nil
            case ERL_ERROR:
                return nil
            default:
                return try termDecoder.decode(Result.self, from: buffer)
            }
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
                    throw ErlangNodeError.rpcFailed
                }
            }
        }
    }
    
    public init(
        name: String,
        cookie: String
    ) throws {
        erlang.ei_init()
        
        guard ei_connect_init(&node.node, name, cookie, UInt32(time(nil) + 1)) >= 0
        else { throw ErlangNodeError.initFailed }
    }
    
    /// Establishes a connection between this node and a remote node.
    public func connect(
        to serverName: String,
        as name: String
    ) async throws -> Connection {
        let fileDescriptor = ei_connect(&node.node, strdup(serverName))
        
        guard fileDescriptor >= 0
        else { throw ErlangNodeError.connectionFailed }
        
        guard ei_global_register(fileDescriptor, name, ei_self(&node.node)) == 0
        else { throw ErlangNodeError.registerFailed }
        
        return Connection(fileDescriptor: fileDescriptor, node: node)
    }
    
    enum ErlangNodeError: Error {
        case initFailed
        case connectionFailed
        case registerFailed
        
        case notConnected
        
        case failedToSend
        case failedToReceive
        
        case rpcFailed
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
            return try await connection.rpc(
                lhs,
                rhs,
                arguments
                    .dropFirst()
                    .map({
                        guard let encodable = $0 as? any Encodable
                        else { throw RPCError.invalidArgument($0) }
                        return encodable
                    })
            )
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
