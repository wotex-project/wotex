defmodule CoreArchiveSupport do
  @moduledoc false

  import ExUnit.Assertions
  alias Wotex.BLE
  alias Wotex.BLE.CoreBluetooth
  @spec fixture(String.t()) :: {keyword(), String.t()}
  def fixture(mode) do
    path = Path.join(File.cwd!(), "peer-instance-#{System.unique_integer([:positive])}")
    File.mkdir!(path)
    executable = Path.join(path, "peer")
    File.cp!(Path.join(File.cwd!(), "peer"), executable)
    File.chmod!(executable, 0o700)
    File.write!(executable <> ".mode", mode)
    identity = JSON.decode!(File.read!("native_identity.json"))
    {:ok, peer} = CoreBluetooth.Peer.new("01234567-89ab-cdef-0123-456789abcdef")

    ExUnit.Callbacks.on_exit(fn ->
      if File.exists?(executable <> ".trace"), do: eventually(fn -> gone?(pid(executable)) end)
      File.rm_rf!(path)
    end)

    {[
       peer: peer,
       generation: 7,
       pairing: :system,
       timeout: 1500,
       executable: executable,
       executable_sha256: digest(executable),
       guardian: identity["guardian"],
       guardian_sha256: identity["guardian_sha256"]
     ], executable}
  end

  @spec connect(String.t()) :: {BLE.Session.t(), String.t()}
  def connect(mode) do
    {options, path} = fixture(mode)
    assert {:ok, session} = BLE.connect([client: CoreBluetooth] ++ options)
    ExUnit.Callbacks.on_exit(fn -> BLE.disconnect(session) end)
    {session, path}
  end

  @spec records(String.t()) :: [map()]
  def records(path) do
    case File.read(path <> ".trace") do
      {:ok, bytes} ->
        for line <- String.split(bytes, "\n", trim: true),
            {:ok, record} <- [JSON.decode(line)],
            do: record

      _ ->
        []
    end
  end

  @spec pid(String.t()) :: pos_integer()
  def pid(path), do: hd(records(path))["fixture_pid"]
  @spec gone?(pos_integer()) :: boolean()
  def gone?(pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(pid)],
        stderr_to_stdout: true,
        env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
      )

    status != 0
  end

  @spec eventually((-> boolean()), non_neg_integer()) :: :ok
  def eventually(fun, attempts \\ 250)
  def eventually(fun, 0), do: assert(fun.())

  def eventually(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          eventually(fun, attempts - 1)
        )
  end

  @spec digest(String.t()) :: String.t()
  def digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
