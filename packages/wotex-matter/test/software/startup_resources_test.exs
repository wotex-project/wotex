Code.require_file("../support/software/resources.exs", __DIR__)

defmodule Wotex.Matter.NativeStartupResourcesTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Matter.SoftwareResources

  @moduletag :software
  @moduletag :interop
  @moduletag timeout: 120_000
  @generation "0123456789abcdef0123456789abcdef"
  @stages ~w(memory storage storage_directory sdk_storage authority attestation groups factory
             system_state event_loop commissioner)

  test "WMA-V04 startup failures, exceptions and kills release each SDK stage and storage lock" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_STARTUP_RESOURCES_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    observations =
      for stage <- @stages, action <- ~w(fail throw wait) do
        SoftwareResources.with_probe(
          fixture["resource_directory"],
          %{
            "startup_stage" => stage,
            "startup_action" => action
          },
          fn probe ->
            with_port(fixture, fn port, child ->
              open(port, fixture)

              assert SoftwareResources.document!(probe, "startup-stage.json", now() + 10_000) ==
                       %{"stage" => stage, "action" => action}

              started = now()

              status =
                case action do
                  "fail" ->
                    assert %{
                             "id" => "1",
                             "ok" => false,
                             "error" => %{"code" => "controller_start_failed"}
                           } =
                             frame(port, 1_000)

                    0

                  "throw" ->
                    1

                  "wait" ->
                    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(child)])
                    137
                end

              assert_receive {^port, {:exit_status, ^status}}, 1_000
              assert gone?(port, child, started + 1_000)
              refute_receive {^port, {:data, _}}, 0
              native = if action == "wait", do: nil, else: SoftwareResources.final!(probe, status)

              %{
                stage: stage,
                action: action,
                exit_status: status,
                cleanup_ms: now() - started,
                native: native
              }
            end)
          end
        )
        |> Map.put(:recovery, recover!(fixture))
      end

    File.write!(
      fixture["result_path"],
      Jason.encode!(%{status: "passed", observations: observations}),
      [:exclusive]
    )
  end

  defp recover!(fixture) do
    SoftwareResources.with_probe(fixture["resource_directory"], fn probe ->
      with_port(fixture, fn port, _ ->
        open(port, fixture)
        assert %{"id" => "1", "ok" => true} = frame(port, 10_000)

        request(port, "2", "read", %{
          fabric_id: fixture["controller"]["fabric_id"],
          node_id: fixture["node_id"],
          endpoint: fixture["endpoint"],
          cluster: 6,
          member: 0
        })

        assert %{"id" => "2", "ok" => true} = frame(port, 10_000)
        census = SoftwareResources.quiescent!(probe)
        assert census["objects"]["interaction"]["acquired"] == 1
        assert census["objects"]["read_client"]["acquired"] == 1
        close(port)
        assert_receive {^port, {:exit_status, 0}}, 1_000
        SoftwareResources.final!(probe)
      end)
    end)
  end

  defp with_port(fixture, operation) do
    port =
      Port.open(
        {:spawn_executable, String.to_charlist(fixture["controller"]["executable"])},
        [:binary, :exit_status, :use_stdio, {:line, 131_072}]
      )

    {:os_pid, child} = Port.info(port, :os_pid)

    try do
      operation.(port, child)
    after
      if Port.info(port), do: Port.close(port)
      assert gone?(port, child, now() + 1_000)
    end
  end

  defp open(port, fixture) do
    assert %{"event" => "ready"} = frame(port, 1_000)
    send_frame(port, %{version: 1, event: "flow_open", session_generation: @generation})

    parameters =
      fixture["controller"]
      |> Map.take(~w(storage_path vendor_id fabric_id controller_node_id paa_trust_store))
      |> Map.merge(%{
        "lifecycle" => "persistent",
        "storage_mode" => "open_existing",
        "authority" => "stored"
      })

    request(port, "1", "open", parameters)
  end

  defp close(port) do
    request(port, "close", "close", %{})
    assert %{"id" => "close", "ok" => true} = frame(port, 1_000)
  end

  defp request(port, id, operation, parameters),
    do:
      send_frame(port, %{
        version: 1,
        id: id,
        operation: operation,
        parameters: parameters,
        timeout_ms: 10_000
      })

  defp send_frame(port, value),
    do: assert(Port.command(port, Jason.encode!(value) <> "\n", [:nosuspend]))

  defp frame(port, timeout) do
    assert_receive {^port, {:data, {:eol, bytes}}}, timeout
    Jason.decode!(bytes)
  end

  defp gone?(port, child, deadline) do
    cond do
      Port.info(port) == nil and not File.exists?("/proc/#{child}") ->
        true

      now() >= deadline ->
        false

      true ->
        Process.sleep(1)
        gone?(port, child, deadline)
    end
  end

  defp now, do: SoftwareResources.now()
end
