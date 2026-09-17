defmodule Wotex.OPCUA.OneshotErrorParityInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Error, Open62541}
  @moduletag :interop

  setup_all do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    peer = Jason.decode!(File.read!(config))
    directory = Path.dirname(config)
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")

    options = [
      client: Open62541,
      executable: executable,
      executable_digest: digest(executable),
      guardian: guardian,
      guardian_digest: digest(guardian),
      endpoint: peer["endpoint"],
      security_policy: :basic256sha256,
      security_mode: :sign_and_encrypt,
      client_uri: peer["client_uri"],
      server_uri: peer["server_uri"],
      certificate: peer["certificate"],
      private_key: Path.join(directory, "client.key.der"),
      server_certificate: peer["server_certificate"],
      trust_certificate: Path.join(directory, "ca.der"),
      crl: peer["crl"],
      authentication: %{type: :anonymous}
    ]

    %{peer: peer, options: options}
  end

  test "WOP-S02 one-shot and persistent modes return the same native error code, effect and class",
       context do
    %{peer: peer, options: options} = context
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, {_, closed_port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)

    call = fn method, arguments ->
      %{
        type: :call,
        node_id: method,
        value: %{object_id: peer["object_id"], arguments: arguments}
      }
    end

    stimuli = [
      {"timeout", [], call.(peer["slow_method_id"], [%{type: "UInt32", value: 3000}]), 800,
       :deadline_exceeded},
      {"connection failure", [endpoint: "opc.tcp://127.0.0.1:#{closed_port}/fixture/"],
       %{type: :read, node_id: peer["node_id"]}, 5000, :connection_failed},
      {"Bad status", [], %{type: :read, node_id: "ns=2;s=missing"}, 5000, :remote_error},
      {"unsupported type", [], %{type: :read, node_id: peer["variants_node_id"]}, 5000,
       :unsupported_type},
      {"invalid request", [],
       %{type: :write, node_id: peer["node_id"], value: %{type: "NotAType", value: 1}}, 5000,
       :invalid_value},
      {"authentication failure",
       [authentication: %{type: :username, username: peer["username"], password: "wrong"}],
       %{type: :read, node_id: peer["node_id"]}, 5000, :authentication_failed}
    ]

    for {name, overrides, message, timeout, code} <- stimuli do
      oneshot =
        observe(Keyword.merge(options, [lifecycle: :oneshot] ++ overrides), message, timeout)

      persistent = observe(Keyword.merge(options, overrides), message, timeout)
      assert %{code: ^code} = oneshot, name
      assert oneshot == persistent, name
    end
  end

  # Opens a Session (a one-shot handle opens nothing yet), sends one message and
  # projects the finite error fields a consumer can branch on.
  defp observe(options, message, timeout) do
    case Wotex.OPCUA.connect(options) do
      {:ok, session} ->
        result = Wotex.OPCUA.send(%{session | timeout: timeout}, message)
        Wotex.OPCUA.disconnect(session)
        project(result)

      error ->
        project(error)
    end
  end

  defp project({:error, %Error{} = error}) do
    classified = Error.classify(error)
    %{code: error.code, effect: error.effect, class: classified.class}
  end

  defp project(other), do: other

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
