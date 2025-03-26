import Foundation
import Combine
import erlang

public struct <#PACKAGE_NAME#> {
    static func elixirStart(
        bundlePath: String,
        host: String,
        port: Int,
        secretKeyBase: String
    ) {
        let rootdir = "\(bundlePath)/_elixir_kit_build/"
        let bindir = "\(bundlePath)/_elixir_kit_build/releases/<#VERSION#>"
        let bootdir = "\(bundlePath)/_elixir_kit_build/releases/<#VERSION#>/start"
        let configdir = "\(bundlePath)/_elixir_kit_build/releases/<#VERSION#>/sys"
        let libdir = "\(bundlePath)/_elixir_kit_build/lib"
        let inetrc = "\(bundlePath)/_elixir_kit_build/erl_inetrc"
        
        setenv("BINDIR", bindir, 0)
        setenv("ERL_LIBS", rootdir, 0)
        setenv("RELEASE_SYS_CONFIG", configdir, 0)
        setenv("RELEASE_ROOT", rootdir, 0)
        setenv("SECRET_KEY_BASE", secretKeyBase, 0)
        setenv("PHX_SERVER", "true", 0)
        setenv("PHX_HOST", host, 0)
        setenv("PORT", String(port), 0)
        
        var args: [UnsafeMutablePointer<CChar>?] = [
            "elixir_kit",
            "--",
            "-bindir", bindir,
            "-root", rootdir,
            "-noshell",
            "-start_epmd", "false",
            "-boot", bootdir,
            "-boot_var", "RELEASE_LIB", libdir,
            "-interactive",
            "-pa", rootdir,
            "-kernel", "inetrc", "'\(inetrc)'",
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
                bundlePath: Bundle.module.bundlePath,
                host: host,
                port: port,
                secretKeyBase: secretKeyBase
            )
        }.start()
    }
}
