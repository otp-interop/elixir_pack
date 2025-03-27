defmodule ElixirKit.XCFramework do
  def build(lib_erlangs, package_dir) do
    # create xcframework
    headers = Path.join(Application.app_dir(:elixirkit), "priv/erlang_include")
    System.cmd("xcodebuild",
      ["-create-xcframework"]
      ++ Enum.flat_map(lib_erlangs, &(["-library", &1, "-headers", headers]))
      ++ ["-output", Path.join(package_dir, "liberlang.xcframework")]
    )
  end
end
