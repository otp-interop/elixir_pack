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

  def otp_target("iphonesimulator"), do: "aarch64-apple-iossimulator"
  def otp_target("iphoneos"), do: "aarch64-apple-ios"

  def openssl_target("iphonesimulator"), do: "iossimulator-arm64-xcrun"
  def openssl_target("iphoneos"), do: "ios64-xcrun"
end
