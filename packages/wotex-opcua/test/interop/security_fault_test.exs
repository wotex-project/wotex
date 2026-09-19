defmodule Wotex.OPCUA.SecurityFaultInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Error, Open62541, Session}
  @moduletag :interop

  @corpus "priv/fixtures/native-contract-v1.json"
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
      %{"input" => input, "expectation" => %{"value" => expected}} =
        Map.fetch!(@cases, unquote(id))

      assert input["peer"] == "open62541-c-peer-1"
      options = options(context, @policies[input["policy"]], token(context, input["user_token"]))
      peer = context.peer
      assert {:ok, session} = Wotex.OPCUA.connect(options)
      %Session{handle: %{host: host}} = session
      processes = native_processes(host)
      read = %{type: :read, node_id: peer["node_id"]}
      {:ok, %{"value" => %{"value" => original}}} = Wotex.OPCUA.send(session, read)

      {:ok, subscription} =
        Wotex.OPCUA.subscribe(session, %{node_id: peer["node_id"], publishing_interval_ms: 50})

      reference = subscription.reference

      results = %{
        "read" =>
          match?({:ok, %{"value" => %{"value" => ^original}}}, Wotex.OPCUA.send(session, read)),
        "write" =>
          match?(
            {:ok, %{"status" => 0}},
            Wotex.OPCUA.send(session, %{
              type: :write,
              node_id: peer["node_id"],
              value: %{type: "Double", value: 42.25}
            })
          ),
        "readback" =>
          match?({:ok, %{"value" => %{"value" => 42.25}}}, Wotex.OPCUA.send(session, read)),
        "call" =>
          match?(
            {:ok, %{"outputs" => [%{"value" => 3.5}]}},
            Wotex.OPCUA.send(session, %{
              type: :call,
              node_id: peer["method_id"],
              value: %{
                object_id: peer["object_id"],
                arguments: [%{type: "Double", value: 1.25}, %{type: "Double", value: 2.25}]
              }
            })
          ),
        "browse" => browsed?(session, peer),
        "subscribe" =>
          receive do
            {:wotex_opcua, ^reference, {:ok, %{"value" => %{"value" => value}}, _}} ->
              value in [original, 42.25]
          after
            5000 -> false
          end,
        "cancel" => Wotex.OPCUA.unsubscribe(session, subscription) == :ok
      }

      {active_subscriptions, _} = resources(session, peer)

      {:ok, %{"status" => 0}} =
        Wotex.OPCUA.send(session, %{
          type: :write,
          node_id: peer["node_id"],
          value: %{type: "Double", value: original}
        })

      live_continuations = map_size(:sys.get_state(host).continuations)
      monitor = Process.monitor(host)
      results = Map.put(results, "close", Wotex.OPCUA.disconnect(session) == :ok)
      assert_receive {:DOWN, ^monitor, :process, ^host, _}, 1000
      assert eventually(fn -> not Enum.any?(processes, &os_alive?/1) end, 1000)

      observed = %{
        "operations_succeeded" => Enum.count(input["operations"], &Map.fetch!(results, &1)),
        "active_peer_subscriptions" => active_subscriptions,
        "active_peer_continuations" => live_continuations,
        "active_local_resources" => Enum.count([host | processes], &alive?/1)
      }

      assert observed == expected
      assert Enum.sort(Map.keys(results)) == Enum.sort(input["operations"])
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

  # A malformed encrypted handshake may be rejected by the peer, the native
  # transport, or the finite open deadline, but it never reaches a Session.
  defp allowed_codes(fault) when fault in ["none_downgrade", "unpinned_server"],
    do: [:certificate_invalid, :connection_failed, :deadline_exceeded]

  defp allowed_codes(_), do: [:certificate_invalid, :authentication_failed, :connection_failed]

  # The peer returns every child in one page, so no server continuation is left.
  defp browsed?(session, peer) do
    case Wotex.OPCUA.Browse.references(session, peer["object_id"]) do
      {:ok, %Wotex.OPCUA.Browse.Page{status: 0, continuation: nil, references: references}} ->
        Enum.any?(
          references,
          &(Wotex.OPCUA.Address.to_string(&1.node_id.node_id) == peer["method_id"])
        )

      _ ->
        false
    end
  end

  defp native_processes(host) do
    %{port: port} = :sys.get_state(host)
    {:os_pid, guardian} = Port.info(port, :os_pid)

    {children, 0} =
      System.cmd("/usr/bin/pgrep", ["-P", Integer.to_string(guardian)], env: [{"LC_ALL", "C"}])

    [guardian | Enum.map(String.split(children), &String.to_integer/1)]
  end

  defp alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp alive?(pid), do: os_alive?(pid)

  defp os_alive?(pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(pid)],
        stderr_to_stdout: true,
        env: [{"LC_ALL", "C"}]
      )

    status == 0
  end

  defp eventually(check, budget_ms) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    poll(check, deadline)
  end

  defp poll(check, deadline) do
    cond do
      check.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        poll(check, deadline)
    end
  end

  test "WOP-S03 user tokens follow the token policy's encryption algorithm", context do
    username = token(context, "username")

    algorithm = fn session, peer ->
      assert {:ok, %{"status" => 0, "outputs" => [%{"value" => value}]}} =
               Wotex.OPCUA.send(session, %{
                 type: :call,
                 node_id: peer["token_method_id"],
                 value: %{object_id: peer["object_id"], arguments: []}
               })

      value
    end

    # The default peer names SecurityPolicy None for UserName tokens, so the
    # password travels unencrypted inside the SignAndEncrypt channel only.
    assert {:ok, session} = Wotex.OPCUA.connect(options(context, :basic256sha256, username))
    assert algorithm.(session, context.peer) == ""
    assert :ok = Wotex.OPCUA.disconnect(session)

    {_, port} = variant(context, "encrypted_tokens", [])

    variant_peer =
      Jason.decode!(File.read!(Path.join(context.directory, "config-encrypted_tokens.json")))

    try do
      for {policy, expected} <- [
            {:basic256sha256, "http://www.w3.org/2001/04/xmlenc#rsa-oaep"},
            {:aes128_sha256_rsaoaep, "http://www.w3.org/2001/04/xmlenc#rsa-oaep"},
            {:aes256_sha256_rsapss, "http://opcfoundation.org/UA/security/rsa-oaep-sha2-256"}
          ] do
        options = options(context, policy, username, endpoint: variant_peer["endpoint"])
        assert {:ok, session} = Wotex.OPCUA.connect(options)
        assert algorithm.(session, variant_peer) == expected
        assert :ok = Wotex.OPCUA.disconnect(session)
      end
    after
      stop_peer(port)
    end
  end

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
    peer = context.peer["executable"]

    port =
      Port.open({:spawn_executable, peer}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 4096},
        {:args, [context.directory, name]}
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
