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
    
    struct CNode: @unchecked Sendable {
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
        var node: CNode
        
        let termDecoder = TermDecoder()
        
        var messageTask: Task<(), Never>?
        var messageStreams = [AsyncStream<Result<ErlangTermBuffer, Error>>.Continuation]()
        
        fileprivate init(
            fileDescriptor: Int32,
            node: CNode
        ) {
            self.fileDescriptor = fileDescriptor
            self.node = node
        }
        
        deinit {
            ei_close_connection(self.fileDescriptor)
        }
        
        fileprivate func startMessageTask() {
            guard self.messageTask == nil else { return }
            
            let fileDescriptor = self.fileDescriptor
            
            self.messageTask = Task.detached { [weak self] in
                while true {
                    var message = erlang_msg()
                    var buffer = ErlangTermBuffer()
                    buffer.new()
                    
                    switch ei_xreceive_msg(fileDescriptor, &message, &buffer.buffer) {
                    case ERL_TICK:
                        print("tick")
                        continue
                    case ERL_ERROR:
                        for stream in await self?.messageStreams ?? [] {
                            stream.yield(.failure(ErlangNodeError.receiveFailed))
                        }
                        continue
                    default:
                        // check if this is a function `:call`
                        // {:call, id, sender, [args...]}
                        let bufferCopy = ErlangTermBuffer()
                        bufferCopy.new()
                        bufferCopy.append(buffer)
                        var index: Int32 = 0
                        var version: Int32 = 0
                        bufferCopy.decode(version: &version, index: &index)
                        
                        var arity: Int32 = 0
                        var atom: [CChar] = [CChar](repeating: 0, count: Int(MAXATOMLEN))
                        if bufferCopy.decode(tupleHeader: &arity, index: &index),
                           arity > 1,
                           bufferCopy.decode(atom: &atom, index: &index),
                           String(cString: atom) == "call"
                        {
                            var id: Int = 0
                            bufferCopy.decode(long: &id, index: &index)
                            var sender: erlang_pid = erlang_pid()
                            bufferCopy.decode(pid: &sender, index: &index)
                            do {
                                nonisolated(unsafe) let arguments = ErlangTermBuffer()
                                arguments.new()
                                arguments.append(buffer)
                                let result = try await Term.Function.call(callee: Term.PID(pid: message.to), id: id, arguments: arguments, argumentsStartIndex: index)
                                try! await self?.send(result, to: Term.PID(pid: sender))
                            } catch {
                                let errorBuffer = try! Term.tuple([.atom("error"), .binary(Data(error.localizedDescription.utf8))]).makeBuffer()
                                try! await self?.send(errorBuffer, to: Term.PID(pid: sender))
                            }
                            continue
                        }
                        
                        for stream in await self?.messageStreams ?? [] {
                            // marked nonisolated(unsafe) due to bug(?) with `sending T` on `yield`.
                            // the value is safe to send, as it is never accessed again in this task,
                            // but the compiler still complains about a possible data race.
                            let bufferCopy = ErlangTermBuffer()
                            bufferCopy.new()
                            bufferCopy.append(buffer)
                            nonisolated(unsafe) let result = Result<ErlangTermBuffer, any Error>.success(bufferCopy)
                            stream.yield(result)
                        }
                    }
                }
            }
        }
        
        public var messages: some AsyncSequence<Result<Term, Error>, Never> {
            AsyncStream { continuation in
                self.messageStreams.append(continuation)
            }
            .compactMap { result in
                if case let .success(buffer) = result {
                    var index: Int32 = 0
                    var version: Int32 = 0
                    buffer.decode(version: &version, index: &index)
                    
                    var arity: Int32 = 0
                    var atom: [CChar] = [CChar](repeating: 0, count: Int(MAXATOMLEN))
                    if buffer.decode(tupleHeader: &arity, index: &index),
                       buffer.decode(atom: &atom, index: &index),
                       let atom = String(cString: atom, encoding: .utf8),
                       atom == "rex" || atom == "call"
                    {
                        // ignore RPC and function call messages
                        return nil
                    }
                }
                return result.flatMap { buffer in
                    return Result {
                        try Term(from: buffer)
                    }
                }
            }
        }
        
        public func messages<Message: Decodable>(
            as type: Message.Type = Message.self
        ) -> some AsyncSequence<Result<Message, Error>, Never> {
            AsyncStream { continuation in
                self.messageStreams.append(continuation)
            }
            .compactMap { result in
                if case let .success(buffer) = result {
                    var index: Int32 = 0
                    var version: Int32 = 0
                    buffer.decode(version: &version, index: &index)
                    
                    var arity: Int32 = 0
                    var atom: [CChar] = [CChar](repeating: 0, count: Int(MAXATOMLEN))
                    if buffer.decode(tupleHeader: &arity, index: &index),
                       buffer.decode(atom: &atom, index: &index),
                       let atom = String(cString: atom, encoding: .utf8),
                       atom == "rex" || atom == "call"
                    {
                        // ignore RPC and function call messages
                        return nil
                    }
                }
                return result.flatMap { buffer in
                    return Result {
                        try TermDecoder().decode(Message.self, from: buffer)
                    }
                }
            }
        }
        
        func messageBuffers() -> some AsyncSequence<Result<ErlangTermBuffer, Error>, Never> {
            AsyncStream { continuation in
                self.messageStreams.append(continuation)
            }
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
            
            guard ei_reg_send(
                &node.node,
                fileDescriptor,
                strdup(process),
                buffer.buff,
                buffer.index
            ) >= 0
            else { throw ErlangNodeError.sendFailed }
        }
        
        public func send(
            _ message: Term,
            to pid: Term.PID
        ) throws {
            let buffer = try Term.tuple([
                .pid(.init(pid: ei_self(&node.node).pointee)),
                message
            ]).makeBuffer()
            
            var pid = pid.pid
            
            guard ei_send(
                fileDescriptor,
                &pid,
                buffer.buff,
                buffer.index
            ) >= 0
            else { throw ErlangNodeError.sendFailed }
        }
        
        /// Send any  ``Swift/Encodable`` type to a named process on a remote
        /// node.
        public func send(
            _ message: some Encodable,
            to process: String
        ) throws {
            var buffer = ErlangTermBuffer()
            buffer.newWithVersion()
            
            buffer.encode(tupleHeader: 2)
            buffer.encode(pid: ei_self(&node.node))
            
            let encoder = TermEncoder()
            encoder.includeVersion = false
            buffer.append(try encoder.encode(message))
            
            guard ei_reg_send(
                &node.node,
                fileDescriptor,
                strdup(process),
                buffer.buff,
                buffer.index
            ) >= 0
            else { throw ErlangNodeError.sendFailed }
        }
        
        public func send(
            _ message: some Encodable,
            to pid: Term.PID
        ) throws {
            var buffer = ErlangTermBuffer()
            buffer.newWithVersion()
            
            buffer.encode(tupleHeader: 2)
            buffer.encode(pid: ei_self(&node.node))
            
            let encoder = TermEncoder()
            encoder.includeVersion = false
            buffer.append(try encoder.encode(message))
            
            var pid = pid.pid
            guard ei_send(
                fileDescriptor,
                &pid,
                buffer.buff,
                buffer.index
            ) >= 0
            else { throw ErlangNodeError.sendFailed }
        }
        
        func send(
            _ message: ErlangTermBuffer,
            to pid: Term.PID
        ) throws {
            var pid = pid.pid
            
            guard ei_send(
                fileDescriptor,
                &pid,
                message.buff,
                message.index
            ) >= 0
            else { throw ErlangNodeError.sendFailed }
        }
        
        /// Receives one message from a remote node, or `nil` if there are no
        /// messages to receive.
        public func receive() throws -> Term? {
            return try receive().flatMap({
                var buffer = $0
                return try Term(from: buffer)
            })
        }
        
        /// Receives one ``Swift/Decodable`` message from a remote node, or
        /// `nil` if there are no messages to receive.
        public func receive<Result: Decodable>() throws -> Result? {
            return try receive().flatMap({ try termDecoder.decode(Result.self, from: $0) })
        }
        
        private func receive() throws -> ErlangTermBuffer? {
            var message = erlang_msg()
            var buffer = ErlangTermBuffer()
            buffer.new()
            
            switch ei_xreceive_msg_tmo(self.fileDescriptor, &message, &buffer.buffer, 1) {
            case ERL_TICK:
                return nil
            case ERL_ERROR:
                return nil
            default:
                return buffer
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
        
        let connection = Connection(fileDescriptor: fileDescriptor, node: node)
        await connection.startMessageTask()
        
        return connection
    }
    
    public var pid: Term.PID {
        .init(pid: ei_self(&node.node).pointee)
    }
    
    enum ErlangNodeError: Error {
        case initFailed
        case connectionFailed
        case registerFailed
        
        case notConnected
        
        case sendFailed
        case receiveFailed
    }
}
