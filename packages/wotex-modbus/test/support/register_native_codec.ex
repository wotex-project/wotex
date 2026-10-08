defmodule Wotex.Modbus.RegisterNativeCodec do
  @moduledoc false

  alias Wotex.Modbus.RegisterCodec
  alias Wotex.Runtime.Codec.Wire

  @spec build!(Path.t()) :: map()
  def build!(workspace) do
    :absolute = Path.type(workspace)

    if File.exists?(workspace) and File.ls!(workspace) != [],
      do: raise("reference workspace must be empty")

    File.mkdir_p!(workspace)
    package = Path.expand("../..", __DIR__)
    native = Path.join(package, "test/native")
    cpp = Path.join(workspace, "register-cpp")
    rust_target = Path.join(workspace, "rust-target")
    cargo = Path.join(native, "register_codec_rust/Cargo.toml")

    run!("c++", [
      "-std=c++17",
      "-O2",
      "-Wall",
      "-Wextra",
      "-Werror",
      Path.join(native, "register_codec_cpp/main.cpp"),
      "-o",
      cpp
    ])

    run!("cargo", [
      "build",
      "--release",
      "--frozen",
      "--offline",
      "--manifest-path",
      cargo,
      "--target-dir",
      rust_target
    ])

    rust = Path.join(rust_target, "release/wotex-modbus-register-reference")
    {compiler, 0} = System.cmd("c++", ["--version"], env: environment())
    {rustc, 0} = System.cmd("rustc", ["--version"], env: environment())
    {commit, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: package, env: environment())
    commit = String.trim(commit)
    true = Regex.match?(~r/\A[0-9a-f]{40}\z/, commit)

    source_files =
      Path.wildcard(Path.join(native, "register_codec_{cpp,rust}/**/*"))
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    receipt = %{
      "schema" => "wotex.register-codec-reference-build@1",
      "repository_commit" => commit,
      "package_path" => "packages/wotex-modbus",
      "test_inputs" =>
        Map.new(
          ~w(test/support/register_native_codec.ex test/wotex/modbus/register_native_codec_test.exs
             test/test_helper.exs priv/fixtures/register_codec/contract.json
             priv/fixtures/register_codec/configuration.schema.json),
          &{&1, digest(Path.join(package, &1))}
        ),
      "contract" => RegisterCodec.contract(),
      "configuration_schema" => RegisterCodec.configuration_schema(),
      "target" => to_string(:erlang.system_info(:system_architecture)),
      "cpp_compiler" => hd(String.split(compiler, "\n")),
      "rust_compiler" => String.trim(rustc),
      "sources" => Map.new(source_files, &{Path.relative_to(&1, package), digest(&1)}),
      "executables" => %{"cpp" => digest(cpp), "rust" => digest(rust)},
      "classification" =>
        "functional reference build; no native enforcement or offline adoption qualification"
    }

    File.write!(
      Path.join(workspace, "reference-build.json"),
      Jason.encode!(receipt, pretty: true) <> "\n"
    )

    %{cpp: cpp, rust: rust, receipt: receipt}
  end

  defp run!(command, args) do
    case System.cmd(command, args, stderr_to_stdout: true, env: environment()) do
      {_, 0} -> :ok
      {output, _} -> raise "reference build failed: #{output}"
    end
  end

  defp environment do
    allowed =
      ~w(PATH HOME TMPDIR TMP TEMP CARGO_HOME RUSTUP_HOME RUSTUP_TOOLCHAIN SDKROOT DEVELOPER_DIR)

    Enum.map(System.get_env(), fn {key, value} ->
      {key, if(key in allowed, do: value, else: nil)}
    end)
  end

  defp digest(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  @spec start(Path.t()) :: port()
  def start(executable) do
    env = Enum.map(System.get_env(), fn {key, _} -> {String.to_charlist(key), false} end)

    Port.open({:spawn_executable, executable}, [
      :binary,
      :use_stdio,
      :exit_status,
      :stderr_to_stdout,
      :hide,
      {:args, []},
      {:env, env}
    ])
  end

  @spec send_bytes(port(), binary()) :: true
  def send_bytes(port, bytes), do: Port.command(port, bytes)

  @spec receive_frame(port()) :: {map(), binary()}
  def receive_frame(port) do
    {:ok, wire} = Wire.new(%{frame_bytes: 131_072, queue_bytes: 262_144})
    receive_frame(port, wire, <<>>)
  end

  defp receive_frame(port, wire, bytes) do
    receive do
      {^port, {:data, chunk}} ->
        case Wire.feed(wire, chunk) do
          {:ok, [], next} -> receive_frame(port, next, bytes <> chunk)
          {:ok, [frame], %{buffer: <<>>}} -> {frame, bytes <> chunk}
          other -> raise "unexpected reference frame: #{inspect(other)}"
        end

      {^port, {:exit_status, code}} ->
        raise "reference exited before reply: #{code}"
    after
      2000 -> raise "reference reply expired"
    end
  end

  @spec exit_status(port()) :: non_neg_integer()
  def exit_status(port) do
    receive do
      {^port, {:exit_status, code}} -> code
      {^port, {:data, _}} -> raise "unexpected reference output before exit"
    after
      2000 -> raise "reference exit expired"
    end
  end

  @spec close(port()) :: :ok
  def close(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  end

  @spec collect(port()) :: {binary(), non_neg_integer()}
  def collect(port), do: collect(port, <<>>)

  defp collect(port, bytes) do
    receive do
      {^port, {:data, chunk}} when byte_size(bytes) + byte_size(chunk) <= 262_144 ->
        collect(port, bytes <> chunk)

      {^port, {:exit_status, code}} ->
        {bytes, code}
    after
      2000 -> raise "reference output/exit expired or exceeded its bound"
    end
  end
end
