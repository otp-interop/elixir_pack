defmodule ElixirKit.Utils do
  def otp_version do
    major = :erlang.system_info(:otp_release) |> List.to_string()
    vsn_file = Path.join([:code.root_dir(), "releases", major, "OTP_VERSION"])

    try do
      {:ok, contents} = File.read(vsn_file)
      String.split(contents, "\n", trim: true)
    else
      [full] -> full
      _ -> major
    catch
      :error, _ -> major
    end
  end

  def gen_secret do
    original_gl = Process.group_leader()
    {:ok, capture_gl} = StringIO.open("")
    try do
        Process.group_leader(self(), capture_gl)
        try do
          Mix.Task.run("phx.gen.secret")
        catch
          _kind, _reason ->
            _ = StringIO.close(capture_gl)
            "" # fallback to an empty string for projects that don't use Phoenix
        else
          _ ->
            {:ok, {_input, output}} = StringIO.close(capture_gl)
            output
              |> String.trim()
              |> String.split("\n")
              |> List.last()
        end
    after
        Process.group_leader(self(), original_gl)
    end
  end

  def otp_target("iphoneos"), do: "aarch64-apple-ios"
  def otp_target("iphonesimulator-arm64"), do: "aarch64-apple-iossimulator"
  def otp_target("iphonesimulator-x86_64"), do: "x86_64-apple-iossimulator"
  def otp_target("macosx-arm64"), do: "aarch64-apple-darwin"
  def otp_target("macosx-x86_64"), do: "x86_64-apple-darwin"

  def openssl_target("iphoneos"), do: "ios64-xcrun"
  def openssl_target("iphonesimulator-arm64"), do: "iossimulator-arm64-xcrun"
  def openssl_target("iphonesimulator-x86_64"), do: "iossimulator-x86_64-xcrun"
  def openssl_target("macosx-arm64"), do: "darwin64-arm64-cc"
  def openssl_target("macosx-x86_64"), do: "darwin64-x86_64-cc"

  def xcomp_conf(otp_src, "iphoneos"), do: Path.join([otp_src, "xcomp", "erl-xcomp-arm64-ios.conf"])
  def xcomp_conf(otp_src, "iphonesimulator-arm64"), do: Path.join([otp_src, "xcomp", "erl-xcomp-arm64-iossimulator.conf"])
  def xcomp_conf(otp_src, "iphonesimulator-x86_64"), do: Path.join([otp_src, "xcomp", "erl-xcomp-x86_64-iossimulator.conf"])
  def xcomp_conf(otp_src, "macosx-arm64"), do: Path.join(Application.app_dir(:elixirkit), "priv/xcomp/erl-xcomp-arm64-macos.conf")
  def xcomp_conf(otp_src, "macosx-x86_64"), do: Path.join(Application.app_dir(:elixirkit), "priv/xcomp/erl-xcomp-x86_64-macos.conf")
end
