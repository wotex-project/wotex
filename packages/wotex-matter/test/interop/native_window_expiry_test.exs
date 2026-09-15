defmodule Wotex.Matter.NativeWindowExpiryTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Error, Native, OnboardingMaterial}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 240_000

  test "an enhanced window expires and its material cannot commission a new fabric" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_WINDOW_FIXTURE") |> File.read!() |> Jason.decode!()

    original = Map.fetch!(fixture, "controller")
    node = %{fabric_id: original["fabric_id"], node_id: Map.fetch!(fixture, "node_id")}

    elapsed =
      with_session(original, :open_existing, :stored, fn session ->
        assert_window_status(session, node, 0)

        assert {:ok, %OnboardingMaterial{} = material} =
                 Matter.open_commissioning_window(session, %{
                   node_id: node.node_id,
                   timeout_s: 180,
                   iteration_count: 10_000,
                   discriminator: Map.fetch!(fixture, "discriminator")
                 })

        opened = System.monotonic_time(:millisecond)
        assert material.expires_in_s == 180
        assert inspect(material) == "#Wotex.Matter.OnboardingMaterial<redacted>"
        assert_window_status(session, node, 1)
        wait_until(opened + 180_200)
        elapsed = System.monotonic_time(:millisecond) - opened
        assert elapsed >= 180_000
        assert_window_status(session, node, 0)

        with_session(fixture["new_controller"], :create_new, :generate_root, fn newcomer ->
          assert {:error, %Error{code: :timeout, effect: :none, details: %{sdk_status: 0x32}}} =
                   Matter.commission_on_network(newcomer, %{
                     node_id: Map.fetch!(fixture, "new_node_id"),
                     setup_pin: material.setup_pin,
                     discriminator: material.discriminator,
                     timeout: 1_000
                   })
        end)

        elapsed
      end)

    File.write!(
      Map.fetch!(fixture, "result_path"),
      Jason.encode!(%{
        status: "passed",
        window_statuses: [0, 1, 0],
        elapsed_before_attempt_ms: elapsed,
        sdk_status: 0x32,
        effect: "none",
        owned_children_after_cleanup: 0
      }),
      [:exclusive]
    )
  end

  defp assert_window_status(session, node, status) do
    address = Map.merge(node, %{endpoint: 0, cluster: 0x003C, member: 0})

    assert {:ok, %AttributeReport{value: %{type: :u8, value: ^status}}} =
             Matter.read_attribute(session, address)
  end

  defp with_session(controller, mode, authority, operation) do
    config =
      [
        client: Native,
        lifecycle: :persistent,
        storage_mode: mode,
        authority: authority,
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
      operation.(session)
    after
      assert :ok = Matter.disconnect(session)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1_000
      assert child_stopped?(child, 100)
    end
  end

  defp wait_until(deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      Process.sleep(min(remaining, 1_000))
      wait_until(deadline)
    end
  end

  defp child_stopped?(_, 0), do: false

  defp child_stopped?(pid, remaining) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        child_stopped?(pid, remaining - 1)

      _ ->
        true
    end
  end
end
