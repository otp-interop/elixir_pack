defmodule ElixirKit.OpenSSL do
  def build(target, prefix, build_dir) do
    openssl_dir = Path.join(build_dir, "_openssl")
    url = "https://www.openssl.org/source/openssl-1.1.1v.tar.gz"

    File.mkdir_p!(openssl_dir)

    tar_path = Path.join(openssl_dir, "openssl-1.1.1v.tar.gz")

    System.cmd("curl", ["--output", tar_path, "-L", url])

    System.cmd("tar", ["xzf", tar_path], cd: openssl_dir)

    openssl_src = Path.join(openssl_dir, "openssl-1.1.1v")

    conf = """
    my %targets = (
        "ios-common" => {
            template         => 1,
            inherit_from     => [ "darwin-common" ],
            sys_id           => "iOS",
            disable          => [ "shared", "async" ],
        },
        "ios-xcrun" => {
            inherit_from     => [ "ios-common", asm("armv4_asm") ],
            CC               => "xcrun -sdk iphoneos cc",
            cflags           => add("-arch armv7 -mios-version-min=7.0.0 -fno-common"),
            perlasm_scheme   => "ios32",
        },
        "ios64-xcrun" => {
            inherit_from     => [ "ios-common", asm("aarch64_asm") ],
            CC               => "xcrun -sdk iphoneos cc",
            cflags           => add("-arch arm64 -mios-version-min=7.0.0 -fno-common"),
            bn_ops           => "SIXTY_FOUR_BIT_LONG RC4_CHAR",
            perlasm_scheme   => "ios64",
        },
        "iossimulator-xcrun" => {
            inherit_from     => [ "ios-common" ],
            CC               => "xcrun -sdk iphonesimulator cc",
        },
        "iossimulator-x86_64-xcrun" => {
            inherit_from     => [ "ios-common" ],
            CC               => "xcrun -sdk iphonesimulator cc",
            cflags           => add("-arch x86_64 -mios-simulator-version-min=7.0.0 -fno-common"),
        },
        "iossimulator-arm64-xcrun" => {
            inherit_from     => [ "ios-common" ],
            CC               => "xcrun -sdk iphonesimulator cc",
            cflags           => add("-arch arm64 -mios-simulator-version-min=7.0.0 -fno-common"),
        },
    );
    """

    File.write!(Path.join(openssl_src, "Configurations/15-ios.conf"), conf)

    System.cmd(Path.join(openssl_src, "Configure"), [target, "--prefix=#{prefix}"], cd: openssl_src)

    System.cmd("make", ["clean"], cd: openssl_src)
    System.cmd("make", ["depend"], cd: openssl_src)
    System.cmd("make", [], cd: openssl_src)
    System.cmd("make", ["install_sw", "install_ssldirs"], cd: openssl_src)
  end
end
