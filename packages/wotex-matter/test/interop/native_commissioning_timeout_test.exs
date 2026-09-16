Code.require_file("../support/software/scenarios.exs", __DIR__)

defmodule Wotex.Matter.NativeCommissioningTimeoutTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Matter
  alias Wotex.Matter.{Error, Native, SoftwareScenarios}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 120_000

  test "the SDK commissioning timeout retains its status before the native owner retires" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_TIMEOUT_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    result =
      SoftwareScenarios.with_peer(fixture, fn ->
        controller = Map.fetch!(fixture, "controller")

        config =
          [
            client: Native,
            lifecycle: :persistent,
            storage_mode: :create_new,
            authority: :generate_root,
            timeout: 60_000
          ] ++
            Enum.map(
              [
                :executable,
                :storage_path,
                :vendor_id,
                :fabric_id,
                :controller_node_id,
                :paa_trust_store
              ],
              &{&1, Map.fetch!(controller, Atom.to_string(&1))}
            )

        assert {:ok, session} = Matter.connect(config)
        owner = session.handle.pid
        monitor = Process.monitor(owner)
        {:links, links} = Process.info(owner, :links)
        [port] = Enum.filter(links, &is_port/1)
        {:os_pid, child} = Port.info(port, :os_pid)

        try do
          assert {:error, %Error{code: :timeout, effect: :none, details: %{sdk_status: 0x32}}} =
                   Matter.commission_on_network(session, %{
                     node_id: Map.fetch!(fixture, "node_id"),
                     setup_pin: Map.fetch!(fixture, "setup_pin"),
                     discriminator: Map.fetch!(fixture, "discriminator"),
                     timeout: 1_000
                   })

          assert {:error, %Error{code: :transport_closed}} = Native.health(session.handle)
        after
          assert :ok = Matter.disconnect(session)
          assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1_000
          assert child_stopped?(child, 100)
        end

        %{
          status: "passed",
          sdk_status: 0x32,
          effect: "none",
          controller_retired_after_timeout: true,
          owned_children_after_cleanup: 0
        }
      end)

    File.write!(Map.fetch!(fixture, "result_path"), Jason.encode!(result), [:exclusive])
  end

  defp child_stopped?(_, 0), do: false

  defp child_stopped?(pid, remaining) do
    case Wotex.Matter.Native.ProcessCommand.run("kill", ["-0", Integer.to_string(pid)],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Process.sleep(10)
        child_stopped?(pid, remaining - 1)

      _ ->
        true
    end
  end
end
