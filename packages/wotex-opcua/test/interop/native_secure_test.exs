defmodule Wotex.OPCUA.NativeSecureInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias Wotex.OPCUA.Native.{Frame, Host, Ready}
  @moduletag :interop

  test "a pinned native SDK channel activates and reads the server NamespaceArray" do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    probe = System.fetch_env!("WOTEX_OPCUA_NATIVE_PROBE")
    parameters = Path.join(Path.dirname(config), "native-open.json")

    assert File.regular?(probe)
    assert File.regular?(parameters)

    {output, 0} =
      System.cmd(probe, [parameters],
        stderr_to_stdout: true,
        env: [{"OPENSSL_CONF", nil}, {"OPENSSL_MODULES", nil}, {"LD_PRELOAD", nil}]
      )

    assert %{
             "status" => "passed",
             "secure_session" => true,
             "namespaces" => 3,
             "revised_ms" => revised
           } = Jason.decode!(output)

    assert revised > 0 and revised <= 60_000
  end

  test "the production native process opens a secure Session and closes it" do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    parameters = Jason.decode!(File.read!(Path.join(Path.dirname(config), "native-open.json")))
    port = Port.open({:spawn_executable, executable}, [:binary, :exit_status])
    on_exit(fn -> if Port.info(port), do: Port.close(port) end)

    {ready_line, <<>>} = line(port, <<>>)
    assert {:ok, %Ready{} = ready} = Ready.decode(ready_line)
    assert {:ok, credit} = Frame.credit(1, 1, 16, 262_144)
    assert {:ok, open} = Frame.request(1, "open-1", "open", parameters, 5000, ready.clock_ms + 5000)
    assert Port.command(port, credit <> open)
    {response, <<>>} = line(port, <<>>)

    assert %{
             "version" => 1,
             "generation" => 1,
             "id" => "open-1",
             "ok" => true,
             "result" => %{
               "session_generation" => 1,
               "session_timeout_ms" => timeout,
               "namespace_array" => ["http://opcfoundation.org/UA/" | _]
             }
           } = Jason.decode!(response)

    assert timeout > 0 and timeout <= 60_000
    assert {:ok, close} = Frame.request(1, "close-1", "close", %{}, 5000, ready.clock_ms + 5000)
    assert Port.command(port, close)
    {close_response, <<>>} = line(port, <<>>)

    assert %{"version" => 1, "generation" => 1, "id" => "close-1", "ok" => true, "result" => nil} =
             Jason.decode!(close_response)

    assert_receive {^port, {:exit_status, 0}}, 5000
  end

  test "the BEAM owner correlates the secure open and close responses" do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    parameters = Jason.decode!(File.read!(Path.join(Path.dirname(config), "native-open.json")))
    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    assert {:ok, host, _} =
             Host.start_link(
               executable: executable,
               executable_digest: digest.(executable),
               guardian: guardian,
               guardian_digest: digest.(guardian),
               timeout: 5000
             )

    assert {:ok,
            %{
              "session_generation" => generation,
              "session_timeout_ms" => timeout,
              "namespace_array" => ["http://opcfoundation.org/UA/" | _]
            }} = Host.request(host, "open", parameters, 5000)

    assert is_integer(generation) and generation > 0
    assert timeout > 0 and timeout <= 60_000
    assert {:ok, nil} = Host.request(host, "close", %{}, 5000)
  end

  defp line(port, buffered) do
    case :binary.match(buffered, "\n") do
      {index, 1} ->
        size = index + 1
        {binary_part(buffered, 0, size), binary_part(buffered, size, byte_size(buffered) - size)}

      :nomatch ->
        receive do
          {^port, {:data, chunk}} -> line(port, buffered <> chunk)
          {^port, {:exit_status, code}} -> flunk("native process exited before a frame: #{code}")
        after
          5000 -> flunk("native frame timed out")
        end
    end
  end
end
