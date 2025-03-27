defmodule Mix.Tasks.Elixirkit do
  use Mix.Task

  @shortdoc "Cross-compiles OTP and releases the project for native platforms"

  @moduledoc """
  Cross-compiles OTP and releases the project for native platforms.

  ## Arguments

      mix elixirkit /output/for/package --sdk SDK [--overwrite]

  ## SDKs

    * `iphoneos` - iOS
    * `iphonesimulator` - iOS Simulator for Apple Silicon

  ## Environment Variables

  Configure the `mix release` with environment variables like `MIX_ENV=prod`.

  If `SECRET_KEY_BASE` is not provided, a secret will be generated with `mix phx.gen.secret`.
  """

  def run(args) do
    # setup sdk
    {options, [output]} =
      OptionParser.parse!(
        args,
        strict: [
          sdk: :keep,
          overwrite: :boolean
        ]
      )

    # setup swift package
    Mix.shell().info("Creating Swift Package at #{output}")
    package_dir = Path.expand(output)
    package_name = Path.basename(package_dir)

    if File.exists?(package_dir) do
      if options[:overwrite] == true or Mix.shell().yes?("A package already exists at #{output}. Overwrite it?") do
        File.rm_rf(package_dir)
      else
        raise "Could not overwrite existing package."
      end
    end

    version = Mix.Project.get().project()[:version]
    secret_key_base =
      System.get_env("SECRET_KEY_BASE") ||
        ElixirKit.Utils.gen_secret()

    template_package = Path.join(Application.app_dir(:elixirkit), "priv/package")
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

    build_dir = Path.join(Path.expand("_build"), "_elixirkit")
    File.mkdir_p!(build_dir)
    resources_dir = Path.join(package_dir, "Sources/#{package_name}/_elixirkit_build")
    File.mkdir_p(resources_dir)
    mix_release_dir = Path.join(build_dir, "rel")

    # compile all beam files
    Mix.shell().info("Creating a Mix release")
    Mix.Task.run("release", ["--path", mix_release_dir, "--overwrite"])

    # build for each sdk
    lib_erlangs = for sdk <- Keyword.get_values(options, :sdk) do
      Mix.shell().info("Building for #{sdk}")

      build_dir = Path.join(build_dir, sdk)

      otp_target = ElixirKit.Utils.otp_target(sdk)
      openssl_target = ElixirKit.Utils.openssl_target(sdk)

      openssl_dir = Path.join([build_dir, "openssl_build"])
      lib_crypto = Path.join(openssl_dir, "lib/libcrypto.a")
      if not File.exists?(lib_crypto) do
        Mix.shell().info("Building OpenSSL")
        ElixirKit.OpenSSL.build(openssl_target, openssl_dir, build_dir)
      end

      Mix.shell().info("Building OTP")
      lib_erlang = ElixirKit.OTP.build(sdk, otp_target, openssl_dir, build_dir)

      lib_erlang
    end

    Mix.shell().info("Creating erlang XCFramework")
    ElixirKit.XCFramework.build(lib_erlangs, package_dir)

    Mix.shell().info("Finalizing Swift Package")
    ElixirKit.SwiftPackage.build(resources_dir, mix_release_dir)

    # patches
    Mix.shell().info("Applying patches to build")

    # create inetrc to prevent crashes with :inet.get_host
    File.write!(Path.join(resources_dir, "erl_inetrc"), """
    {edns,0}.
    {alt_nameserver, {8,8,8,8}}.
    {lookup, [dns]}.
    """)
  end
end
