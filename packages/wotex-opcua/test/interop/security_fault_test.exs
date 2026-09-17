defmodule Wotex.OPCUA.SecurityFaultInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Error, Open62541, Session}
  @moduletag :interop

  @corpus "docs/specs/fixtures/native-contract-v1.json"
  @corpus_sha256 :crypto.hash(:sha256, File.read!(@corpus)) |> Base.encode16(case: :lower)
  @cases Map.new(Jason.decode!(File.read!(@corpus))["cases"], &{&1["id"], &1})
  @policies %{
    "Basic256Sha256" => :basic256sha256,
    "Aes128_Sha256_RsaOaep" => :aes128_sha256_rsaoaep,
    "Aes256_Sha256_RsaPss" => :aes256_sha256_rsapss
  }

  setup_all do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    %{peer: Jason.decode!(File.read!(config)), directory: Path.dirname(config)}
  end

  for number <- 30..38 do
    id = "WOP-X-F#{number}"

    @tag case: id, corpus_sha256: @corpus_sha256
    test "#{id} secure policy and user token execute every listed service", context do
      input = Map.fetch!(@cases, unquote(id))["input"]
      options = options(context, @policies[input["policy"]], token(context, input["user_token"]))
      assert {:ok, session} = Wotex.OPCUA.connect(options)
      peer = context.peer

      assert {:ok, %{"value" => %{"value" => original}}} =
               Wotex.OPCUA.send(session, %{type: :read, node_id: peer["node_id"]})

      assert {:ok, %{"status" => 0}} =
               Wotex.OPCUA.send(session, %{
                 type: :write,
                 node_id: peer["node_id"],
                 value: %{type: "Double", value: 42.25}
               })

      assert {:ok, %{"value" => %{"value" => 42.25}}} =
               Wotex.OPCUA.send(session, %{type: :read, node_id: peer["node_id"]})

      assert {:ok, %{"outputs" => [%{"value" => 3.5}]}} =
               Wotex.OPCUA.send(session, %{
                 type: :call,
                 node_id: peer["method_id"],
                 value: %{
                   object_id: peer["object_id"],
                   arguments: [%{type: "Double", value: 1.25}, %{type: "Double", value: 2.25}]
                 }
               })

      assert {:ok, children} =
               Wotex.OPCUA.send(session, %{type: :browse, node_id: peer["object_id"]})

      assert peer["method_id"] in children

      assert {:ok, subscription} =
               Wotex.OPCUA.subscribe(session, %{
                 node_id: peer["node_id"],
                 publishing_interval_ms: 50
               })

      reference = subscription.reference
      assert_receive {:wotex_opcua, ^reference, {:ok, %{"value" => %{"value" => 42.25}}, _}}, 5000
      assert {1, 1} = resources(session, peer)
      assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
      assert {0, 0} = resources(session, peer)

      assert {:ok, %{"status" => 0}} =
               Wotex.OPCUA.send(session, %{
                 type: :write,
                 node_id: peer["node_id"],
                 value: %{type: "Double", value: original}
               })

      %Session{handle: %{host: host}} = session
      monitor = Process.monitor(host)
      assert :ok = Wotex.OPCUA.disconnect(session)
      assert_receive {:DOWN, ^monitor, :process, ^host, _}, 1000
    end
  end

  test "WOP-V07 rejected user credentials fail activation without anonymous fallback", context do
    for authentication <- [
          %{type: :username, username: context.peer["username"], password: "wrong"},
          %{type: :username, username: "unknown", password: context.peer["password"]},
          %{
            type: :certificate,
            certificate: Path.join(context.directory, "stranger.der"),
            private_key: Path.join(context.directory, "stranger.key.der")
          }
        ] do
      options = options(context, :basic256sha256, authentication)

      assert {:error, %Error{code: :authentication_failed, details: details}} =
               Wotex.OPCUA.connect(options)

      assert Bitwise.band(details.status, 0x8000_0000) != 0
    end
  end

  for {number, fault} <- [
        {39, "expired_leaf"},
        {40, "wrong_host"},
        {41, "wrong_application_uri"},
        {42, "untrusted_ca"},
        {43, "revoked_leaf"},
        {44, "expired_crl"},
        {45, "mismatched_private_key"},
        {46, "none_downgrade"},
        {47, "unsupported_user_token"}
      ] do
    id = "WOP-X-F#{number}"

    @tag case: id, corpus_sha256: @corpus_sha256
    test "#{id} #{fault} fails before an application request", context do
      expected = Map.fetch!(@cases, unquote(id))["expectation"]["value"]
      assert Map.fetch!(@cases, unquote(id))["input"]["fault"] == unquote(fault)
      {options, peer} = fault_options(context, unquote(fault))
      began = System.monotonic_time(:millisecond)

      try do
        assert {:error, %Error{code: code, effect: :none}} =
                 Wotex.OPCUA.connect(Keyword.put(options, :timeout, 2000))

        assert System.monotonic_time(:millisecond) - began < 3000
        assert code in allowed_codes(unquote(fault))
        assert expected["authenticated"] == false
        assert expected["application_requests"] == 0
        assert expected["active_local_resources"] == 0
        refute_received {:wotex_opcua_native, _, _}
      after
        stop_peer(peer)
      end
    end
  end

  test "WOP-S03 a pinned leaf presented by a different server fails during the handshake",
       context do
    {options, peer} = fault_options(context, "unpinned_server")

    try do
      assert {:error, %Error{code: code}} =
               Wotex.OPCUA.connect(Keyword.put(options, :timeout, 2000))

      assert code in allowed_codes("unpinned_server")
    after
      stop_peer(peer)
    end
  end

  # asyncua 2.0.1 neither answers nor closes an OpenSecureChannel request that
  # it cannot decrypt or that uses a policy it does not offer, so those two
  # rejections end at the finite open deadline without a Session.
  defp allowed_codes(fault) when fault in ["none_downgrade", "unpinned_server"],
    do: [:certificate_invalid, :connection_failed, :deadline_exceeded]

  defp allowed_codes(_), do: [:certificate_invalid, :authentication_failed, :connection_failed]

  defp resources(session, peer) do
    assert {:ok, %{"status" => 0, "outputs" => [%{"value" => subscriptions}, %{"value" => items}]}} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: peer["resources_method_id"],
               value: %{object_id: peer["object_id"], arguments: []}
             })

    {subscriptions, items}
  end

  defp token(_, "anonymous"), do: %{type: :anonymous}

  defp token(context, "username"),
    do: %{type: :username, username: context.peer["username"], password: context.peer["password"]}

  defp token(context, "certificate"),
    do: %{
      type: :certificate,
      certificate: Path.join(context.directory, "user.der"),
      private_key: Path.join(context.directory, "user.key.der")
    }

  defp options(context, policy, authentication, overrides \\ []) do
    peer = context.peer
    directory = context.directory
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")

    Keyword.merge(
      [
        client: Open62541,
        executable: executable,
        executable_digest: digest(executable),
        guardian: guardian,
        guardian_digest: digest(guardian),
        endpoint: peer["endpoint"],
        security_policy: policy,
        security_mode: :sign_and_encrypt,
        client_uri: peer["client_uri"],
        server_uri: peer["server_uri"],
        certificate: peer["certificate"],
        private_key: Path.join(directory, "client.key.der"),
        server_certificate: peer["server_certificate"],
        trust_certificate: Path.join(directory, "ca.der"),
        crl: peer["crl"],
        authentication: authentication
      ],
      overrides
    )
  end

  # Client-side faults reuse the default peer; server-side faults start a
  # variant peer that shares the generated credentials.
  defp fault_options(context, fault) do
    directory = context.directory
    anonymous = %{type: :anonymous}

    case fault do
      "expired_leaf" ->
        variant(context, "expired_leaf", server_certificate: "expired.der")

      "wrong_host" ->
        variant(context, "wrong_host", server_certificate: "wronghost.der")

      "unpinned_server" ->
        variant(context, "wrong_host", [])

      "none_downgrade" ->
        variant(context, "none_only", [])

      "unsupported_user_token" ->
        {variant_options, peer} = variant(context, "anonymous_only", [])
        {Keyword.put(variant_options, :authentication, token(context, "username")), peer}

      "wrong_application_uri" ->
        {options(context, :basic256sha256, anonymous, server_uri: "urn:wotex:fixture:other"), nil}

      "untrusted_ca" ->
        {options(context, :basic256sha256, anonymous,
           trust_certificate: Path.join(directory, "other-ca.der")
         ), nil}

      "revoked_leaf" ->
        {options(context, :basic256sha256, anonymous, crl: Path.join(directory, "revoked.crl")),
         nil}

      "expired_crl" ->
        {options(context, :basic256sha256, anonymous, crl: Path.join(directory, "expired.crl")),
         nil}

      "mismatched_private_key" ->
        {options(context, :basic256sha256, anonymous,
           private_key: Path.join(directory, "other.key.der")
         ), nil}
    end
  end

  defp variant(context, name, files) do
    python = context.peer["executable"]
    script = Path.expand("secure_peer.py", __DIR__)

    port =
      Port.open({:spawn_executable, python}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 4096},
        {:args, [script, context.directory, name]}
      ])

    await_ready(port, System.monotonic_time(:millisecond) + 15_000)
    peer = Jason.decode!(File.read!(Path.join(context.directory, "config-#{name}.json")))

    overrides =
      [endpoint: peer["endpoint"]] ++
        Enum.map(files, fn {key, file} -> {key, Path.join(context.directory, file)} end)

    {options(context, :basic256sha256, %{type: :anonymous}, overrides), port}
  end

  defp stop_peer(nil), do: :ok

  defp stop_peer(port) do
    {:os_pid, pid} = Port.info(port, :os_pid)
    Port.close(port)

    System.cmd("/bin/kill", ["-TERM", Integer.to_string(pid)],
      stderr_to_stdout: true,
      env: [{"LC_ALL", "C"}]
    )

    :ok
  end

  defp await_ready(port, deadline) do
    timeout = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, {:eol, "secure peer ready"}}} -> :ok
      {^port, {:data, _}} -> await_ready(port, deadline)
      {^port, {:exit_status, status}} -> flunk("variant peer exited: #{status}")
    after
      timeout -> flunk("variant peer did not become ready")
    end
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
