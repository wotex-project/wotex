defmodule Wotex.OPCUA.NativeSecureInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false
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
end
