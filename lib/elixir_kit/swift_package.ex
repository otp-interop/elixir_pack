defmodule ElixirKit.SwiftPackage do
  def build(otp_release, application, package_dir) do
    resources_dir = Path.join(package_dir, "Sources/ElixirKit/_elixir_kit_build")

    File.cp_r!(otp_release, resources_dir) # copy otp build

    ebin = Path.expand(Application.app_dir(:elixir, "ebin"))
    for beam <- Path.wildcard(Path.join(ebin, "*.beam")) do
      File.cp!(beam, Path.join(resources_dir, Path.basename(beam)))
    end
    ebin = Path.expand(Application.app_dir(application, "ebin"))
    for beam <- Path.wildcard(Path.join(ebin, "*.beam")) do
      File.cp!(beam, Path.join(resources_dir, Path.basename(beam)))
    end

    for file <- Path.wildcard(Path.join(otp_release, "**/*")) do
      path = Path.join(resources_dir, Path.relative_to(file, otp_release))
        |> Path.expand()
      if File.dir?(file) do
        File.mkdir_p(path)
      else
        File.cp!(file, path)
      end
    end
  end
end
