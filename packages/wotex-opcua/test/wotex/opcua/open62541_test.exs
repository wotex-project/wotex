defmodule Wotex.OPCUA.Open62541Test do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Browse, Error, Open62541}

  @options [
    executable: "/missing/native",
    executable_digest: String.duplicate("a", 64),
    guardian: "/missing/guardian",
    guardian_digest: String.duplicate("b", 64),
    endpoint: "opc.tcp://127.0.0.1:4840/fixture/",
    security_policy: :basic256sha256,
    security_mode: :sign_and_encrypt,
    client_uri: "urn:wotex:test:client",
    server_uri: "urn:wotex:test:server",
    certificate: "/missing/client.der",
    private_key: "/missing/client.key.der",
    server_certificate: "/missing/server.der",
    trust_certificate: "/missing/ca.der",
    crl: "/missing/clean.crl",
    authentication: %{type: :anonymous}
  ]

  setup_all do
    directory =
      Path.join(System.tmp_dir!(), "wotex-opcua-client-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    compiler = System.find_executable("cc") || flunk("native client tests require a C11 compiler")
    root = Path.expand("../../..", __DIR__)

    for {source, output} <- [
          {"priv/native/custody.c", "guardian"},
          {"test/native/host_probe.c", "probe"}
        ] do
      {diagnostic, status} =
        System.cmd(
          compiler,
          [
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            Path.join(root, source),
            "-o",
            Path.join(directory, output)
          ],
          stderr_to_stdout: true,
          env: [{"CFLAGS", nil}, {"LDFLAGS", nil}]
        )

      assert status == 0, diagnostic
    end

    %{directory: directory}
  end

  test "WOP-X01 one-shot connection validates configuration without reading files" do
    assert {:ok, handle} = Open62541.connect(Keyword.put(@options, :lifecycle, :oneshot))
    assert :ok = Open62541.disconnect(handle)
    assert :ok = Open62541.disconnect(handle)

    assert {:error, %Error{code: :invalid_native_configuration}} =
             Open62541.connect([{:security_mode, :none} | @options])

    assert {:error, %Error{code: :invalid_native_configuration}} = Open62541.connect(%{})
  end

  test "WOP-X01 invalid operations fail before one-shot file or process I/O" do
    assert {:ok, handle} = Open62541.connect(Keyword.put(@options, :lifecycle, :oneshot))

    for message <- [
          %{type: :read, node_id: "bad"},
          %{type: :read, node_id: "i=1", index_range: "1:2"},
          %{type: :write, node_id: "i=1", value: %{type: "Double", value: "not a number"}},
          %{type: :write, node_id: "i=1", value: %{type: "NodeId", value: "i=2"}},
          %{type: :write, node_id: "i=1", index_range: "1:2", value: %{type: "Double", value: 4.5}},
          %{type: :write, node_id: "i=1", value: 4.5},
          %{
            type: :write,
            node_id: "i=1",
            value: %{:type => "Double", "type" => "Double", :value => 4.5}
          },
          %{
            type: :call,
            node_id: "i=2",
            value: %{
              object_id: "i=85",
              arguments: List.duplicate(%{type: "Double", value: 1.0}, 65)
            }
          },
          %{type: :call, node_id: "i=2", value: %{object_id: "i=85", arguments: [], extra: true}}
        ] do
      assert {:error, %Error{}} = Open62541.request(handle, message, 100)
    end

    assert {:error, %Error{code: :invalid_node_id}} =
             Open62541.request(handle, %{type: :browse, node_id: "bad"}, 100)

    assert {:error, %Error{code: :invalid_value}} =
             Open62541.request(handle, %{type: :browse, node_id: "i=85", extra: true}, 100)

    assert {:error, %Error{code: :unsupported_protocol}} =
             Open62541.request(handle, %{type: :browse_next, node_id: "i=85"}, 100)

    assert {:error, %Error{code: :invalid_native_handle}} =
             Open62541.request(handle, %{type: :read, node_id: "i=1"}, 0)

    assert {:error, %Error{code: :invalid_native_handle}} = Open62541.disconnect(%{})

    assert {:error, %Error{code: :invalid_native_handle}} =
             Open62541.request(%{handle | host: :forged}, %{type: :read, node_id: "i=1"}, 100)
  end

  test "WOP-X04 the facade retains no-effect for locally rejected native mutations" do
    assert {:ok, session} =
             Wotex.OPCUA.connect(
               @options
               |> Keyword.put(:lifecycle, :oneshot)
               |> Keyword.put(:client, Open62541)
             )

    assert {:error, %Error{code: :invalid_value, effect: :none}} =
             Wotex.OPCUA.send(session, %{
               type: :write,
               node_id: "ns=2;s=value",
               value: %{type: "Double", value: "bad"}
             })

    assert {:error, %Error{code: :invalid_value, effect: :none}} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: "ns=2;s=method",
               value: %{object_id: "ns=0;i=85", arguments: [42]}
             })
  end

  test "WOP-X01 persistent connect rejects missing credential files before process startup" do
    assert {:error, %Error{code: :invalid_native_configuration}} =
             Open62541.connect(@options)
  end

  test "WOP-X01 persistent native client owns open, services and close", context do
    options = fixture(context, "persistent")
    assert {:ok, handle} = Open62541.connect(options)

    assert {:ok, %{"value" => %{"value" => 21.5}}} =
             Open62541.request(handle, %{type: :read, node_id: "ns=2;s=value"}, 1000)

    assert {:ok, %{"status" => 0}} =
             Open62541.request(
               handle,
               %{type: :write, node_id: "ns=2;s=value", value: %{type: "Double", value: 4.5}},
               1000
             )

    assert {:ok, %{"status" => 0}} =
             Open62541.request(
               handle,
               %{
                 type: :write,
                 node_id: "ns=2;s=value",
                 value: %{type: "ByteString", value: <<0, 255>>}
               },
               1000
             )

    assert {:ok, %{"status" => 0}} =
             Open62541.request(
               handle,
               %{
                 type: :write,
                 node_id: "ns=2;s=value",
                 value: %{"type" => "ByteString", "array" => true, "value" => [<<0, 255>>, nil]}
               },
               1000
             )

    assert {:ok, %{"status" => 0}} =
             Open62541.request(
               handle,
               %{
                 type: :write,
                 node_id: "ns=2;s=value",
                 value: %{"type" => "Double", "value" => 4.5}
               },
               1000
             )

    assert {:ok, %{"outputs" => [%{"value" => 4.5}]}} =
             Open62541.request(
               handle,
               %{
                 type: :call,
                 node_id: "ns=2;s=method",
                 value: %{
                   object_id: "ns=0;i=85",
                   arguments: [%{type: "Double", value: 1.25}, %{type: "Double", value: 3.25}]
                 }
               },
               1000
             )

    assert {:ok, ["ns=1;s=value"]} =
             Open62541.request(handle, %{type: :browse, node_id: "ns=0;i=85"}, 1000)

    assert :ok = Open62541.disconnect(handle)
    assert :ok = Open62541.disconnect(handle)
  end

  test "WOP-N03 a complete native Browse page retains typed references and strict options",
       context do
    options = fixture(context, "typed-browse")
    assert {:ok, session} = Wotex.OPCUA.connect(Keyword.put(options, :client, Open62541))

    assert {:ok, %Browse.Page{status: 0, continuation: nil, references: [reference]}} =
             Browse.references(session, "ns=0;i=85", page_size: 16)

    assert reference.reference_type_id ==
             %Wotex.OPCUA.Address{namespace: 0, kind: :numeric, identifier: 35}

    assert reference.node_id.node_id ==
             %Wotex.OPCUA.Address{namespace: 1, kind: :string, identifier: "value"}

    assert reference.browse_name == %{namespace: 1, name: "Value"}
    assert reference.display_name == %{locale: nil, text: "Value"}
    assert reference.node_class == 2

    for opts <- [
          [page_size: 0],
          [page_size: 257],
          [page_size: 1, page_size: 2],
          [direction: :sideways],
          [node_class_mask: 256],
          [max_pages: 0],
          [max_references: 0],
          [timeout_ms: 0],
          [unexpected: true]
        ] do
      assert {:error, %Error{code: :invalid_value}} =
               Browse.references(session, "ns=0;i=85", opts)
    end

    assert {:error, %Error{code: :invalid_node_id}} =
             Browse.references(session, "bad")

    assert :ok = Wotex.OPCUA.disconnect(session)

    assert {:ok, oneshot} =
             Wotex.OPCUA.connect(
               @options
               |> Keyword.put(:client, Open62541)
               |> Keyword.put(:lifecycle, :oneshot)
             )

    assert {:error, %Error{code: :persistent_session_required}} =
             Browse.references(oneshot, "ns=0;i=85")

    assert :ok = Wotex.OPCUA.disconnect(oneshot)

    remote_options = fixture(context, "typed-remote-browse", "session_remote_browse")

    assert {:ok, remote} =
             Wotex.OPCUA.connect(Keyword.put(remote_options, :client, Open62541))

    assert {:ok, %Browse.Page{references: [remote_reference]}} =
             Browse.references(remote, "ns=0;i=85")

    assert remote_reference.node_id.server_index == 1
    assert remote_reference.node_id.node_id.namespace == 1
    assert :ok = Wotex.OPCUA.disconnect(remote)

    unknown_options = fixture(context, "typed-unknown-browse", "session_unknown_browse")

    assert {:ok, unknown} =
             Wotex.OPCUA.connect(Keyword.put(unknown_options, :client, Open62541))

    assert {:error, %Error{code: :unsupported_remote_reference}} =
             Browse.references(unknown, "ns=0;i=85")

    assert :ok = Wotex.OPCUA.disconnect(unknown)

    duplicate_options = fixture(context, "typed-duplicate-browse", "session_two_browse")

    assert {:ok, duplicate_session} =
             Wotex.OPCUA.connect(Keyword.put(duplicate_options, :client, Open62541))

    assert {:error, %Error{code: :response_limit}} =
             Browse.references(duplicate_session, "ns=0;i=85", max_references: 1)

    assert {:ok, %Browse.Page{references: [first, second]}} =
             Browse.references(duplicate_session, "ns=0;i=85", max_references: 2)

    assert first == second
    assert :ok = Wotex.OPCUA.disconnect(duplicate_session)

    assert {:error, %Error{code: :unsupported_protocol}} =
             Browse.references(
               %Wotex.OPCUA.Session{client: Wotex.OPCUA.Asyncua, handle: %{}, timeout: 1000},
               "i=1"
             )
  end

  test "WOP-X01 one-shot native client opens and closes within each read", context do
    options = fixture(context, "oneshot")
    assert {:ok, handle} = Open62541.connect(Keyword.put(options, :lifecycle, :oneshot))

    assert {:ok, %{"type" => "Double", "value" => 21.5, "status" => 0} = read} =
             Open62541.request(handle, %{type: :read, node_id: "ns=2;s=value"}, 2000)

    assert {:ok, 21.5, %{opcua_type: "Double", status: 0}} = Wotex.OPCUA.Value.result(read)

    assert :ok = Open62541.disconnect(handle)
  end

  test "WOP-N04 one-shot Write and Call preserve compatibility result shapes", context do
    write_options = fixture(context, "oneshot-write")

    assert {:ok, write_handle} =
             Open62541.connect(Keyword.put(write_options, :lifecycle, :oneshot))

    assert {:ok, "written"} =
             Open62541.request(
               write_handle,
               %{type: :write, node_id: "ns=2;s=value", value: %{type: "Double", value: 4.5}},
               2000
             )

    call_options = fixture(context, "oneshot-call")
    assert {:ok, call_handle} = Open62541.connect(Keyword.put(call_options, :lifecycle, :oneshot))

    assert {:ok, 4.5} =
             Open62541.request(
               call_handle,
               %{
                 type: :call,
                 node_id: "ns=2;s=method",
                 value: %{
                   object_id: "ns=0;i=85",
                   arguments: [%{type: "Double", value: 1.25}, %{type: "Double", value: 3.25}]
                 }
               },
               2000
             )
  end

  test "WOP-N04 one-shot Call preserves zero and multiple output shapes", context do
    call = %{
      type: :call,
      node_id: "ns=2;s=method",
      value: %{object_id: "ns=0;i=85", arguments: []}
    }

    for {mode, expected} <- [{"session_empty_call", nil}, {"session_many_call", [4.5, true]}] do
      options = fixture(context, mode, mode)
      assert {:ok, handle} = Open62541.connect(Keyword.put(options, :lifecycle, :oneshot))
      assert {:ok, ^expected} = Open62541.request(handle, call, 2000)
    end
  end

  test "WOP-N04 one-shot ByteString arrays retain legacy binary envelopes", context do
    options = fixture(context, "bytes-read", "session_bytes_read")
    assert {:ok, handle} = Open62541.connect(Keyword.put(options, :lifecycle, :oneshot))

    assert {:ok,
            %{
              "type" => "ByteString",
              "status" => 0,
              "value" => [
                %{"type" => "ByteString", "base64" => "AP8="},
                %{"type" => "ByteString", "base64" => "AQ=="}
              ]
            }} = Open62541.request(handle, %{type: :read, node_id: "ns=2;s=value"}, 2000)
  end

  test "WOP-N04 one-shot Read rejects absent or legacy-unrepresentable values", context do
    for mode <- ["session_empty_read", "session_localized_read", "session_localized_array_read"] do
      options = fixture(context, mode, mode)
      assert {:ok, handle} = Open62541.connect(Keyword.put(options, :lifecycle, :oneshot))

      assert {:error, %Error{code: :unsupported_type}} =
               Open62541.request(handle, %{type: :read, node_id: "ns=2;s=value"}, 2000)
    end
  end

  test "WOP-N04 one-shot Call rejects an output without a legacy JSON shape", context do
    for mode <- ["session_localized_call", "session_matrix_call"] do
      options = fixture(context, mode, mode)
      assert {:ok, handle} = Open62541.connect(Keyword.put(options, :lifecycle, :oneshot))

      assert {:error, %Error{code: :unsupported_type}} =
               Open62541.request(
                 handle,
                 %{
                   type: :call,
                   node_id: "ns=2;s=method",
                   value: %{object_id: "ns=0;i=85", arguments: []}
                 },
                 2000
               )
    end
  end

  test "WOP-I01 Runtime ByteString Form writes raw bytes through the native client", context do
    alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}

    options = fixture(context, "runtime-bytes", "session_runtime_bytes")
    endpoint = Keyword.fetch!(options, :endpoint)
    href = endpoint <> "?id=" <> URI.encode_www_form("ns=2;s=value")
    assert {:ok, form} = Wotex.Form.new(%{"href" => href, "wotex:variantType" => "ByteString"})
    assert {:ok, runtime_context} = Context.new(request_id: "native-bytes")

    request = %Request{
      operation: :writeproperty,
      affordance_type: :property,
      affordance_name: "value",
      form: form,
      resolved_href: href,
      profile: nil,
      request_id: "native-bytes",
      deadline: nil,
      input: <<0, 255>>
    }

    config =
      options ++ [client: Open62541, lifecycle: :oneshot, target: endpoint]

    assert {:ok, %Result{payload: "written", status: :ok}} =
             Wotex.OPCUA.Transport.request(
               request,
               ExecutionContext.new(runtime_context, nil),
               config
             )
  end

  test "WOP-I03 Runtime typed ByteString arrays write raw bytes through the native client",
       context do
    alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}

    options = fixture(context, "runtime-byte-array", "session_runtime_byte_array")
    endpoint = Keyword.fetch!(options, :endpoint)
    href = endpoint <> "?id=" <> URI.encode_www_form("ns=2;s=value")
    assert {:ok, form} = Wotex.Form.new(%{"href" => href})
    assert {:ok, runtime_context} = Context.new(request_id: "native-byte-array")

    request = %Request{
      operation: :writeproperty,
      affordance_type: :property,
      affordance_name: "value",
      form: form,
      resolved_href: href,
      profile: nil,
      request_id: "native-byte-array",
      deadline: nil,
      input: %{type: "ByteString", array: true, value: [<<0, 255>>, nil, <<>>]}
    }

    config = options ++ [client: Open62541, lifecycle: :oneshot, target: endpoint]

    assert {:ok, %Result{payload: "written", status: :ok}} =
             Wotex.OPCUA.Transport.request(
               request,
               ExecutionContext.new(runtime_context, nil),
               config
             )
  end

  test "WOP-N04 one-shot native Browse uses one temporary Session", context do
    options = fixture(context, "oneshot-browse")
    assert {:ok, handle} = Open62541.connect(Keyword.put(options, :lifecycle, :oneshot))

    assert {:ok, ["ns=1;s=value"]} =
             Open62541.request(handle, %{type: :browse, node_id: "ns=0;i=85"}, 2000)

    assert :ok = Open62541.disconnect(handle)
  end

  test "WOP-N04 child projection refuses a remote ExpandedNodeId", context do
    options = fixture(context, "remote-browse", "session_remote_browse")
    assert {:ok, handle} = Open62541.connect(options)

    assert {:error, %Error{code: :unsupported_remote_reference}} =
             Open62541.request(handle, %{type: :browse, node_id: "ns=0;i=85"}, 1000)

    assert :ok = Open62541.disconnect(handle)
  end

  test "WOP-N04 child projection refuses an unknown local namespace", context do
    options = fixture(context, "unknown-browse", "session_unknown_browse")
    assert {:ok, handle} = Open62541.connect(options)

    assert {:error, %Error{code: :unsupported_remote_reference}} =
             Open62541.request(handle, %{type: :browse, node_id: "ns=0;i=85"}, 1000)

    assert :ok = Open62541.disconnect(handle)
  end

  test "WOP-X01 failed secure activation closes the native owner", context do
    options = fixture(context, "badopen", "session_reply")
    options = Keyword.put(options, :session_timeout_ms, 61_000)

    assert {:error, %Error{}} = Open62541.connect(options)

    oneshot_options =
      context
      |> fixture("badopen-oneshot", "session_reply")
      |> Keyword.merge(lifecycle: :oneshot, session_timeout_ms: 61_000)

    assert {:ok, oneshot} = Open62541.connect(oneshot_options)

    assert {:error, %Error{}} =
             Open62541.request(oneshot, %{type: :read, node_id: "ns=2;s=value"}, 2000)
  end

  defp fixture(context, name, mode \\ "session_services") do
    directory = Path.join(context.directory, name)
    File.mkdir!(directory)
    executable = Path.join(directory, mode)
    File.cp!(Path.join(context.directory, "probe"), executable)
    File.chmod!(executable, 0o700)

    files =
      for field <- [:certificate, :private_key, :server_certificate, :trust_certificate, :crl] do
        path = Path.join(directory, Atom.to_string(field) <> ".der")
        File.write!(path, Atom.to_string(field))
        {field, path}
      end

    @options
    |> Keyword.merge(files)
    |> Keyword.merge(
      executable: executable,
      executable_digest: digest(executable),
      guardian: Path.join(context.directory, "guardian"),
      guardian_digest: digest(Path.join(context.directory, "guardian")),
      timeout: 2000
    )
  end

  defp digest(path),
    do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
