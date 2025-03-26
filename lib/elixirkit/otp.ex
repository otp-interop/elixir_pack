defmodule ElixirKit.OTP do
  @make_flags "-j8 -O"
  @c_flags "-fno-common -Os -mios-simulator-version-min=16.0 -mios-version-min=16.0"
  @install_program "/usr/bin/install -c"

  def build(sdk, otp_target, openssl, resources_dir, build_dir) do
    ref = "OTP-#{ElixirKit.Utils.otp_version}"
    url = "https://github.com/erlang/otp"
    otp_src = Path.join(build_dir, "_otp")
    otp_release = Path.expand(resources_dir)

    System.cmd("git", ["clone", "--depth", "1", "--branch", ref, url, otp_src])

    lib_crypto = Path.expand(Path.join(openssl, "lib/libcrypto.a"))
    nif_paths = [
      Path.expand(Path.join(otp_src, "lib/crypto/priv/lib/#{otp_target}/crypto.a")),
      Path.expand(Path.join(otp_src, "lib/asn1/priv/lib/#{otp_target}/asn1rt_nif.a"))
    ]

    env = [
      {"MAKEFLAGS", @make_flags},
      {"ERL_TOP", Path.expand(otp_src)},
      {"ERLC_USE_SERVER", "true"},
      {"RELEASE_LIBBEAM", "yes"},
      {"RELEASE_ROOT", Path.expand(otp_release)},
      {"LIBS", lib_crypto},
      {"INSTALL_PROGRAM", @install_program},
    ]

    otp_include = Path.join("#{:code.root_dir}", "usr/include")

    # configure cross compilation
    {sdk_root, _} = System.cmd("xcrun", ["-sdk", sdk, "--show-sdk-path"])
    xcomp_conf = """
    otp_target=#{otp_target}
    cflags="#{@c_flags} -D__IOS__=yes"
    arch="-arch arm64"
    sdk=#{sdk}

    sdkroot=#{sdk_root}

    erl_xcomp_build=guess
    erl_xcomp_host=$otp_target
    erl_xcomp_configure_flags="--enable-builtin-zlib --disable-jit --without-termcap"
    erl_xcomp_sysroot=$sdkroot

    CC="xcrun -sdk $sdk cc $arch"
    CFLAGS="$cflags"
    CXX="xcrun -sdk $sdk c++ $arch"
    CXXFLAGS=$CFLAGS
    LD="xcrun -sdk $sdk ld $arch"
    LDFLAGS="-L$sdkroot/usr/lib/ -lc++ -v"
    DED_LD=$LD
    DED_LDFLAGS="-L$sdkroot/usr/lib/ -r -v"
    RANLIB="xcrun -sdk $sdk ranlib"
    AR="xcrun -sdk $sdk ar"
    """
    # xcomp_conf_path = Path.join(build_dir, "xcomp.conf")
    # File.write!(xcomp_conf_path, xcomp_conf)

    xcomp_conf_path = Path.join([
      otp_src,
      "xcomp",
      case sdk do
        "iphonesimulator" ->
          "erl-xcomp-arm64-iossimulator.conf"
        "iphoneos" ->
          "erl-xcomp-arm64-ios.conf"
      end
    ])

    # cross compile OTP
    exclusions = ~w(common_test debugger dialyzer diameter edoc eldap erl_docgen et eunit ftp inets jinterface megaco mnesia observer odbc os_man tftp wx xmerl)
    System.cmd(Path.expand(Path.join(otp_src, "otp_build")), [
      "configure",
      "--xcomp-conf=#{Path.expand(xcomp_conf_path)}",
      "--with-ssl=#{Path.expand(openssl)}",
      "--disable-dynamic-ssl-lib",
      "--enable-static-nifs=#{Enum.join(nif_paths, ",")}"
    ] ++ Enum.map(exclusions, &("--without-#{&1}")), cd: Path.expand(otp_src), env: env)

    System.cmd(Path.expand(Path.join(otp_src, "otp_build")), ["boot"], cd: Path.expand(otp_src), env: env)
    System.cmd(Path.expand(Path.join(otp_src, "otp_build")), ["release", Path.expand(otp_release)], cd: Path.expand(otp_src), env: env)
    System.cmd(Path.expand(Path.join(otp_release, "Install")), ["-sasl", Path.expand(otp_release)], cd: Path.expand(otp_release), env: env)

    # collect all otp output files to create liberlang
    {build_arch, 0} = System.cmd(Path.expand(Path.join(otp_src, "erts/autoconf/config.guess")), [], cd: Path.expand(otp_src))
    File.mkdir_p(Path.join(otp_release, "usr/lib"))
    all_libraries = Path.wildcard("#{otp_src}/**/*.a")
    |> Enum.filter(fn lib ->
      String.contains?(lib, otp_target)
      and (not String.contains?(lib, String.trim(build_arch)))
      and (not String.ends_with?(lib, "_st.a"))
      and (not String.ends_with?(lib, "_r.a"))
    end)
    |> Enum.uniq()
    |> Enum.map(&Path.expand(&1))

    lib_erlang = Path.join(otp_release, "/usr/lib/liberlang.a")
    System.cmd("libtool", [
      "-static",
      "-o", lib_erlang,
      lib_crypto,
    ] ++ nif_paths ++ all_libraries)

    lib_erlang
  end
end
