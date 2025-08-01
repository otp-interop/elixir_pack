defmodule ElixirPack.XCFramework do
  def build(lib_erlangs, package_dir, build_dir) do
    # combine `liberlang`s that have the same sdk, but different architectures into a fat binary
    grouped_libs = lib_erlangs
      |> Enum.group_by(fn {sdk, _path} ->
        sdk
        |> String.split("-")
        |> hd()
      end)

    lib_erlangs = for {sdk, arch_libs} <- grouped_libs do
      case arch_libs do
        [{_arch, lib}] ->
          lib
        libs ->
          fat_lib = Path.join([build_dir, sdk, "liberlang.a"])
          File.rm(fat_lib)
          fat_lib
            |> Path.dirname()
            |> File.mkdir_p()

          System.cmd("lipo", ["-create", "-output", fat_lib] ++ Enum.map(libs, &(elem(&1, 1))), into: IO.stream())
          fat_lib
      end
    end

    # create xcframework
    headers = Path.join(Application.app_dir(:elixir_pack), "priv/erlang_include")
    System.cmd("xcodebuild",
      ["-create-xcframework"]
        ++ Enum.flat_map(lib_erlangs, fn lib -> ["-library", lib, "-headers", headers] end)
        ++ ["-output", Path.join(package_dir, "liberlang.xcframework")],
      into: IO.stream()
    )
  end
end
