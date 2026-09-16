defmodule Wotex.CoAP.NativeWorkerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @revision "7cf7465b784baded4de183290c547d582becfd28"
  @source_files ~w(
    native/oscore/main.c
    native/oscore/worker.c
    native/oscore/exchange.c
    native/oscore/custody.c
    native/oscore/command.c
    native/oscore/json.c
    native/oscore/frame.c
    native/oscore/body.c
    native/oscore/credit.c
    native/oscore/observation.c
    native/oscore/identity.c
    native/oscore/store.c
    native/oscore/vendor/yyjson/yyjson.c
  )

  setup_all do
    root =
      Path.join(System.tmp_dir!(), "wotex-coap-worker-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    executable = Path.join(root, "wotex-coap-oscore")
    compiler = System.find_executable("cc") || flunk("native worker tests require a C11 compiler")

    pkg_config =
      System.find_executable("pkg-config") || flunk("native worker tests require pkg-config")

    {openssl, 0} =
      System.cmd(pkg_config, ["--cflags", "--libs", "openssl"], env: clean_environment())

    arguments =
      ~w(-std=c11 -Wall -Wextra -Werror) ++
        [
          "-DYYJSON_DISABLE_NON_STANDARD=1",
          "-DYYJSON_DISABLE_UTILS=1",
          "-DYYJSON_DISABLE_INCR_READER=1",
          "-Inative/oscore"
        ] ++ @source_files ++ String.split(openssl) ++ ["-o", executable]

    {output, status} =
      System.cmd(compiler, arguments,
        stderr_to_stdout: true,
        env: [{"CFLAGS", nil}, {"CPPFLAGS", nil}, {"LDFLAGS", nil}]
      )

    assert status == 0, output
    %{executable: executable, root: root}
  end

  test "WCO-N02/N04 same binary owns durable open, bounded body state and close", context do
    store = store(context.root, "lifecycle")
    port = start_worker(context.executable, store)

    assert read_json(port) == %{
             "version" => 1,
             "event" => "ready",
             "backend" => "libcoap",
             "revision" => @revision
           }

    open_id = ~s(id"\\)
    command(port, open_id, "open", open_parameters(store), 1_000)
    assert read_json(port) == success(open_id)

    body = "ABC"
    body_id = "body-1"

    command(port, "2", "body_begin", %{
      "body_id" => body_id,
      "length" => byte_size(body),
      "sha256" => digest(body)
    })

    assert read_json(port) == success("2")

    command(port, "3", "body_chunk", %{
      "body_id" => body_id,
      "offset" => 0,
      "data" => bytes(body)
    })

    assert read_json(port) == success("3")
    command(port, "4", "body_end", %{"body_id" => body_id})
    assert read_json(port) == success("4")

    command(port, "5", "request", %{
      "method" => "GET",
      "path" => "/value",
      "confirmable" => true,
      "body_id" => body_id
    })

    assert read_json(port) == failure("5", "native_unavailable")

    command(port, "6", "close", %{})
    assert read_json(port) == success("6")
    assert_receive {^port, {:exit_status, 0}}, 2_000

    assert File.exists?(Path.join(store, "context.lock"))
    assert File.exists?(Path.join(store, "contexts.v1"))
  end

  test "WCO-N04 live lock and consumed identity fail with finite store codes", context do
    store = store(context.root, "lease")
    owner = start_worker(context.executable, store)
    assert read_json(owner)["event"] == "ready"
    command(owner, "1", "open", open_parameters(store))
    assert read_json(owner) == success("1")

    contender = start_worker(context.executable, store)
    assert read_json(contender)["event"] == "ready"
    command(contender, "1", "open", open_parameters(store))
    assert read_json(contender) == failure("1", "context_store_locked")
    Port.close(contender)

    command(owner, "2", "close", %{})
    assert read_json(owner) == success("2")
    assert_receive {^owner, {:exit_status, 0}}, 2_000

    reopened = start_worker(context.executable, store)
    assert read_json(reopened)["event"] == "ready"
    command(reopened, "1", "open", open_parameters(store))
    assert read_json(reopened) == failure("1", "fresh_context_required")
    Port.close(reopened)
  end

  test "WCO-N03 malformed input closes the worker generation", context do
    store = store(context.root, "malformed")
    port = start_worker(context.executable, store)
    assert read_json(port)["event"] == "ready"
    assert Port.command(port, ~s({"version":1,"version":1}\n))
    assert_receive {^port, {:exit_status, status}}, 2_000
    refute status == 0
    refute File.exists?(Path.join(store, "context.lock"))
  end

  defp store(root, name) do
    path = Path.join(root, name)
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    File.cd!(path, &File.cwd!/0)
  end

  defp start_worker(executable, store) do
    Port.open(
      {:spawn_executable, String.to_charlist(executable)},
      [:binary, :exit_status, :use_stdio, {:args, [~c"--custody", String.to_charlist(store)]}]
    )
  end

  defp command(port, id, operation, parameters, timeout_ms \\ 1_000) do
    line =
      Jason.encode!(%{
        "version" => 1,
        "id" => id,
        "operation" => operation,
        "parameters" => parameters,
        "timeout_ms" => timeout_ms
      }) <> "\n"

    assert Port.command(port, line)
  end

  defp read_json(port, buffer \\ <<>>) do
    receive do
      {^port, {:data, bytes}} ->
        case :binary.split(buffer <> bytes, "\n") do
          [line, <<>>] when byte_size(line) > 0 -> Jason.decode!(line)
          [_, _] -> flunk("native worker emitted coalesced unsolicited output")
          [_] -> read_json(port, buffer <> bytes)
        end

      {^port, {:exit_status, status}} ->
        flunk("native worker exited before its response with status #{status}")
    after
      2_000 -> flunk("native worker response timed out")
    end
  end

  defp open_parameters(store) do
    %{
      "host" => "127.0.0.1",
      "port" => 5_683,
      "generation" => 1,
      "security" => %{
        "mode" => "oscore",
        "master_secret" => bytes(<<0::128>>),
        "master_salt" => bytes(<<>>),
        "sender_id" => bytes(<<>>),
        "recipient_id" => bytes(<<1>>),
        "id_context" => nil,
        "context_store" => store
      }
    }
  end

  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}

  defp digest(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp clean_environment,
    do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)

  defp success(id), do: %{"version" => 1, "id" => id, "ok" => true, "result" => nil}

  defp failure(id, code),
    do: %{"version" => 1, "id" => id, "ok" => false, "error" => %{"code" => code}}
end
