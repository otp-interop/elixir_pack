import Foundation
import Combine
import erlang

public struct <#PACKAGE_NAME#> {
    static func elixirStart(
        bundle: Bundle,
        host: String,
        port: Int,
        secretKeyBase: String
    ) {
        let rootdir = bundle.path(forResource: "_elixirkit_build", ofType: nil)!
        let bindir = "\(rootdir)/releases/0.1.0"
        let bootdir = "\(bindir)/start"
        let configdir = "\(bindir)/sys"
        let libdir = "\(rootdir)/lib"
        
        setenv("BINDIR", bindir, 0)
        setenv("ERL_LIBS", rootdir, 0)
        setenv("RELEASE_SYS_CONFIG", configdir, 0)
        setenv("RELEASE_ROOT", rootdir, 0)
        setenv("SECRET_KEY_BASE", secretKeyBase, 0)
        setenv("PHX_SERVER", "true", 0)
        setenv("PHX_HOST", host, 0)
        setenv("PORT", String(port), 0)
        
        var args: [UnsafeMutablePointer<CChar>?] = [
            "elixirkit",
            "--",
            "-bindir", bindir,
            "-root", rootdir,
            "-noshell",
            "-start_epmd", "false",
            "-boot", bootdir,
            "-boot_var", "RELEASE_LIB", libdir,
            "-interactive",
            "-pa", rootdir,
            "-kernel", "inet_dist_use_interface", "{127,0,0,1}",
            "-config", configdir,
        ]
            .map {
                $0.withCString { strdup($0) }
            }
        
        erlang.erl_start(Int32(args.count), &args)
    }
    
    public static func start(
        host: String = "127.0.0.1",
        port: Int = 4000,
        secretKeyBase: String = "<#SECRET_KEY_BASE#>"
    ) {
        Thread {
            elixirStart(
                bundle: Bundle.module,
                host: host,
                port: port,
                secretKeyBase: secretKeyBase
            )
        }.start()
    }
}
