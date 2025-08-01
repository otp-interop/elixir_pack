defmodule Mix.Tasks.ElixirPack do
  use Mix.Task

  @shortdoc "Cross-compiles OTP and releases the project for native platforms"

  @moduledoc """
  Cross-compiles OTP and releases the project for native platforms.

  ## Arguments

      mix elixir_pack /output/for/package --target TARGET_A --target TARGET_B [--overwrite]

  ## Targets

    * `iphoneos` - iOS
    * `iphonesimulator-arm64` - iOS Simulator for Apple Silicon
    * `iphonesimulator-x86_64` - iOS Simulator for x86
    * `macosx-arm64` - macOS with Apple Silicon
    * `macosx-x86_64` - macOS with x86

  ## Environment Variables

  Configure the `mix release` with environment variables like `MIX_ENV=prod`.

  If `SECRET_KEY_BASE` is not provided, a secret will be generated with `mix phx.gen.secret`.
  """

  def run(args) do
    {options, [output]} =
      OptionParser.parse!(
        args,
        strict: [
          target: :keep,
          overwrite: :boolean,
          nif: :keep
        ]
      )

    # setup swift package
    package_dir = Path.expand(output)
    package_name = Path.basename(package_dir)
    Mix.shell().info([:green, "* creating ", :reset, "swift package #{package_name} (#{package_dir})"])

    if File.exists?(package_dir) do
      if options[:overwrite] == true or Mix.shell().yes?("A package already exists at #{output}. Overwrite it?") do
        File.rm_rf!(package_dir)
      else
        raise "Could not overwrite existing package."
      end
    end

    version = Mix.Project.get().project()[:version]
    secret_key_base =
      System.get_env("SECRET_KEY_BASE") ||
        ElixirPack.Utils.gen_secret()

    template_package = Path.join(Application.app_dir(:elixir_pack), "priv/package")
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
              |> String.replace("<#VERSION#>", version)
              |> String.replace("<#SECRET_KEY_BASE#>", secret_key_base)
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

    build_dir = Path.join(Path.expand("_build"), "_elixir_pack")
    File.mkdir_p!(build_dir)
    resources_dir = Path.join(package_dir, "Sources/#{package_name}/_elixir_pack")
    File.mkdir_p(resources_dir)
    mix_release_dir = Path.join(build_dir, "rel")

    # compile all beam files
    Mix.shell().info([:green, "* assembling ", :reset, "a mix release"])
    Mix.Task.run("release", ["--path", mix_release_dir, "--overwrite"])

    # build for each target
    lib_erlangs = for target <- Keyword.get_values(options, :target) do
      Mix.shell().info([:green, "* building ", :reset, "#{target}"])

      build_dir = Path.join(build_dir, target)

      otp_target = ElixirPack.Utils.otp_target(target)
      openssl_target = ElixirPack.Utils.openssl_target(target)

      openssl_dir = Path.join([build_dir, "openssl_build"])
      lib_crypto = Path.join(openssl_dir, "lib/libcrypto.a")
      if not File.exists?(lib_crypto) do
        Mix.shell().info([:yellow, "* building ", :reset, "openssl"])
        ElixirPack.OpenSSL.build(openssl_target, openssl_dir, build_dir)
      else
        Mix.shell().info([:green, "* found ", :reset, "openssl"])
      end

      otp_release = Path.join([build_dir, "_otp_release"])
      lib_erlang = Path.join(otp_release, "/usr/lib/liberlang.a")
      if not File.exists?(lib_erlang) do
        Mix.shell().info([:yellow, "* building ", :reset, "otp"])
        otp_release = Path.join([build_dir, "_otp_release"])
        ElixirPack.OTP.build(target, otp_target, openssl_dir, build_dir, otp_release, lib_erlang, Keyword.get_values(options, :nif))
      else
        Mix.shell().info([:green, "* found ", :reset, "otp"])
      end

      {target, lib_erlang}
    end

    Mix.shell().info([:green, "* creating ", :reset, "xcframework"])
    ElixirPack.XCFramework.build(lib_erlangs, package_dir, build_dir)

    Mix.shell().info([:green, "* assembling ", :reset, "swift package"])
    ElixirPack.SwiftPackage.build(resources_dir, mix_release_dir)

    # create inetrc to prevent crashes with :inet.get_host
    File.write!(Path.join(resources_dir, "inetrc"), """
    {edns,0}.
    {alt_nameserver, {8,8,8,8}}.
    {lookup, [dns]}.
    """)
  end
end
