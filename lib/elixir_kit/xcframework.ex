defmodule ElixirKit.XCFramework do
  def build(lib_erlang, package_dir) do
    # create xcframework
    System.cmd("xcodebuild", [
      "-create-xcframework",
      "-library", lib_erlang,
      "-headers", Path.join(Application.app_dir(:elixir_kit), "priv/erlang_include"),
      "-output", Path.join(package_dir, "liberlang.xcframework")
    ])
  end
end
