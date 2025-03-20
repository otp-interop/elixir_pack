defmodule ElixirKit.SwiftPackage do
  def build(resources_dir, application, mix_release_dir, package_dir) do
    # deps = Mix.Project.deps_apps()
    # deps = [:elixir | deps]
    # deps = [application | deps]

    # for dep <- deps do
    # end
    # for beam <- Path.wildcard(Path.join(mix_release_dir, "**/*.{beam,app}")) do
    #   File.cp!(beam, Path.join(resources_dir, Path.basename(beam)))
    # end

    for dep <- Path.wildcard(Path.join([mix_release_dir, "lib", "*"])) do
      IO.puts "copying dep #{dep}"
      File.cp_r(dep, Path.join([resources_dir, "lib", Path.basename(dep)]))
    end

    # for file <- Path.wildcard(Path.join(otp_release, "**/*")) do
    #   path = Path.join(resources_dir, Path.relative_to(file, otp_release))
    #     |> Path.expand()
    #   if File.dir?(file) do
    #     File.mkdir_p(path)
    #   else
    #     File.cp!(file, path)
    #   end
    # end
  end
end
