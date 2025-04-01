defmodule ElixirKit.SwiftPackage do
  def build(resources_dir, mix_release_dir) do
    File.mkdir_p(Path.join(resources_dir, "lib"))
    for dep <- Path.wildcard(Path.join([mix_release_dir, "lib", "*"])) do
      File.cp_r(dep, Path.join([resources_dir, "lib", Path.basename(dep)]))
    end

    # delete the OTP releases file and replace with our mix project's release
    # this gets us the boot scripts and other config files
    File.rm_rf(Path.join(resources_dir, "releases"))
    File.cp_r(Path.join([mix_release_dir, "releases"]), Path.join(resources_dir, "releases"))
  end
end
