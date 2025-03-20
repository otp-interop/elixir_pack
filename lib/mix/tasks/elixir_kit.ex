defmodule Mix.Tasks.ElixirKit do
  use Mix.Task

  def run(args) do
    # setup sdk
    {options, [], []} =
      OptionParser.parse(args, struct: [application: :string, sdk: :string, output: :output])
    options = Enum.into(options, %{})

    otp_target = case options.sdk do
      "iphonesimulator" ->
        "aarch64-apple-iossimulator"
    end
    xcomp_target = case options.sdk do
      "iphonesimulator" ->
        "arm64-iossimulator"
    end
    swift_target = case options.sdk do
      "iphonesimulator" ->
        "arm64-apple-ios18.4-simulator"
    end
    openssl_target = case options.sdk do
      "iphonesimulator" ->
        "iossimulator-arm64-xcrun"
    end

    build_dir = Path.expand("_elixir_kit_build")
    package_dir = Path.expand(options.output)
    package_name = Path.basename(package_dir)
    resources_dir = Path.join(package_dir, "Sources/#{package_name}/_elixir_kit_build")
    mix_release_dir = Path.join(build_dir, "rel")
    openssl_dir = Path.join(build_dir, "openssl_build")

    lib_crypto = Path.join(openssl_dir, "lib/libcrypto.a")
    if not File.exists?(lib_crypto) do
      ElixirKit.OpenSSL.build(openssl_target, openssl_dir, build_dir)
    end

    File.mkdir_p!(build_dir)

    # compile all beam files
    Mix.Task.run("release", ["--path", mix_release_dir, "--overwrite"])

    # setup swift package
    template_package = Path.join(Application.app_dir(:elixir_kit), "priv/package")
    File.cp_r!(template_package, package_dir)
    # rename folders to use the package's name
    for file <- Path.wildcard(Path.join(package_dir, "**/*")) do
      if String.contains?(Path.basename(file), "<#PACKAGE_NAME#>") do
        File.rename(
          file,
          Path.join(
            Path.dirname(file),
            String.replace(Path.basename(file), "<#PACKAGE_NAME#>", package_name)
          )
        )
      end
    end
    for file <- Path.wildcard(Path.join(package_dir, "**/*")) do
      # replace any placeholders in the files
      case File.read(file) do
        {:ok, contents} ->
          File.write!(
            file,
            contents
              |> String.replace("<#PACKAGE_NAME#>", package_name)
              |> String.replace("<#APPLICATION#>", options.application)
          )
        {:error, _} ->
          :noop
      end
      # rename files to use the package's name
      if String.contains?(Path.basename(file), "<#PACKAGE_NAME#>") do
        File.rename(
          file,
          Path.join(
            Path.dirname(file),
            String.replace(Path.basename(file), "<#PACKAGE_NAME#>", package_name)
          )
        )
      end
    end

    # build
    lib_erlang = ElixirKit.OTP.build(options.sdk, otp_target, xcomp_target, openssl_dir, resources_dir, build_dir)

    ElixirKit.XCFramework.build(lib_erlang, package_dir)

    ElixirKit.SwiftPackage.build(resources_dir, String.to_existing_atom(options.application), mix_release_dir, package_dir)

    # patches

    # create inetrc to prevent crashes with :inet.get_host
    File.write!(Path.join(resources_dir, "erl_inetrc"), """
    {edns,0}.
    {alt_nameserver, {8,8,8,8}}.
    {lookup, [dns]}.
    """)


  end
end
