import Observation
import Foundation
import Combine
import erlang

@Observable
public final class <#PACKAGE_NAME#> {
    let thread: Thread
    public let port: Int

    public init(
        host: String = "127.0.0.1",
        port: Int? = nil,
        secretKeyBase: String = "<#SECRET_KEY_BASE#>"
    ) {
        let port = port ?? Self.automaticPort()
        self.port = port
        self.thread = Thread {
            // Phoenix environment variables
            setenv("SECRET_KEY_BASE", secretKeyBase, 0)
            setenv("PHX_SERVER", "true", 0)
            setenv("PHX_HOST", host, 0)
            setenv("PORT", String(port), 0)

            Self.start()
        }
        self.thread.start()
    }

    deinit {
        thread.cancel()
    }

    public static func start(
        with arguments: [String] = []
    ) {
        let rootPath = Bundle.module.path(forResource: "_elixirkit_build", ofType: nil)!
        let binPath = "\(rootPath)/releases/0.1.0"
        let bootPath = "\(binPath)/start"
        let configPath = "\(binPath)/sys"
        let libPath = "\(rootPath)/lib"
        let inetrcPath = "\(rootPath)/inetrc"
        
        setenv("BINDIR", binPath, 0)
        setenv("ERL_LIBS", rootPath, 0)
        setenv("RELEASE_SYS_CONFIG", configPath, 0)
        setenv("RELEASE_ROOT", rootPath, 0)
        setenv("ERL_INETRC", inetrcPath, 0)
        
        var args: [UnsafeMutablePointer<CChar>?] = ([
            "elixirkit",
            "--",
            "-bindir", binPath,
            "-root", rootPath,
            "-noshell",
            "-start_epmd", "false",
            "-boot", bootPath,
            "-boot_var", "RELEASE_LIB", libPath,
            "-interactive",
            "-pa", rootPath,
            "-config", configPath,
        ] + arguments)
            .map {
                $0.withCString { strdup($0) }
            }
        
        erlang.erl_start(Int32(args.count), &args)
    }

    /// Port 4000, used if ``automaticPort`` fails.
    static var fallbackPort: Int { 4000 }
    
    /// Automatic port assignment that falls back to ``fallbackPort``.
    static func automaticPort() -> Int {
        // create a server bound to port 0
        let server = socket(AF_INET, SOCK_STREAM, 0)
        
        guard server != -1 // failed to create
        else { return fallbackPort }
        
        defer { close(server) }
        
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_ANY
        address.sin_port = 0 // auto port assignment
        
        var addressLength = socklen_t(MemoryLayout<sockaddr_in>.stride)
        
        guard withUnsafeMutablePointer(to: &address, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                let isBound = bind(server, $0, addressLength) == 0
                let isAddressSet = getsockname(server, $0, &addressLength) == 0
                return isBound && isAddressSet
            }
        })
        else { return fallbackPort }
        
        guard listen(server, 1) == 0
        else { return fallbackPort }
        
        // connect to the server
        let client = socket(AF_INET, SOCK_STREAM, 0)
        
        guard client != -1 // failed to create
        else { return fallbackPort }
        
        defer { close(client) }
        
        guard withUnsafeMutablePointer(to: &address, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(client, $0, addressLength) == 0
            }
        })
        else { return fallbackPort }
        
        // accept the connection
        let acceptedSocket = accept(server, nil, nil)
        
        guard acceptedSocket != -1 // failed to accept
        else { return fallbackPort }
        
        defer { close(acceptedSocket) }
        
        // return the port assigned to the server
        return Int(address.sin_port.byteSwapped)
    }
}
