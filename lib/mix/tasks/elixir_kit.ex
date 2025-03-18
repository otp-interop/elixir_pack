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
    swift_target = case options.sdk do
      "iphonesimulator" ->
        "arm64-apple-ios18.4-simulator"
    end

    # compile all beam files
    Mix.Task.run("compile")

    build_dir = Path.expand("_elixir_kit_build")
    package_dir = Path.expand(options.output)

    File.mkdir_p!(build_dir)

    # setup swift package
    template_package = Path.join(Application.app_dir(:elixir_kit), "priv/package")
    File.cp_r!(template_package, package_dir)

    # build
    # FIXME: otp release output should just be the `_elixir_kit_build` folder in the Swift package since we just copy it there at the end.
    {otp_release, lib_erlang} = ElixirKit.OTP.build(options.sdk, otp_target, build_dir)

    ElixirKit.XCFramework.build(lib_erlang, package_dir)

    ElixirKit.SwiftPackage.build(otp_release, String.to_existing_atom(options.application), package_dir)
  end
end
