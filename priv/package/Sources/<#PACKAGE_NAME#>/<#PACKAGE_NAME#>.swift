import Foundation
import Combine
import erlang

public struct <#PACKAGE_NAME#> {
    static func elixirStart(bundlePath: String) {
        let rootdir = "\(bundlePath)/_elixir_kit_build/"
        let bindir = "\(bundlePath)/_elixir_kit_build/releases/27"
        let bootdir = "\(bundlePath)/_elixir_kit_build/releases/27/start"
        let libdir = "\(bundlePath)/_elixir_kit_build/lib"
        let inetrc = "\(bundlePath)/_elixir_kit_build/erl_inetrc"
        
        setenv("BINDIR", bindir, 0)
        setenv("ERL_LIBS", rootdir, 0)
        
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
            "-eval", "'Elixir.Application':ensure_all_started(<#APPLICATION#>)",
        ]
            .map {
                $0.withCString { strdup($0) }
            }
        
        erlang.erl_start(Int32(args.count), &args)
    }
    
    public static func start() {
        Thread {
            elixirStart(bundlePath: Bundle.module.bundlePath)
        }.start()
    }
}
