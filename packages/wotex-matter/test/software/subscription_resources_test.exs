Code.require_file("../support/software/resources.exs", __DIR__)
Code.require_file("../support/software/peer.exs", __DIR__)

defmodule Wotex.Matter.NativeSubscriptionResourcesTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Error, Native, SoftwarePeer, SoftwareResources}

  @moduletag :software
  @moduletag :interop
  @moduletag timeout: 240_000

  test "WMA-S04 SDK recovery restores a snapshot and releases timers on success, cancel and expiry" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_SUBSCRIPTION_RESOURCES_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    result =
      SoftwareResources.with_probe(fixture["resource_directory"], fn probe ->
        options =
          [
            client: Native,
            lifecycle: :persistent,
            storage_mode: :create_new,
            authority: :generate_root,
            timeout: 10_000
          ] ++
            Enum.map(
              ~w(executable storage_path vendor_id fabric_id controller_node_id paa_trust_store)a,
              &{&1, Map.fetch!(fixture["controller"], Atom.to_string(&1))}
            )

        assert {:ok, session} = Matter.connect(options)
        port = :sys.get_state(session.handle.pid).port
        {:os_pid, child} = Port.info(port, :os_pid)

        try do
          observations =
            owned(fixture["peer"], 1, fn first ->
              assert {:ok, %{case: :established}} =
                       Matter.commission_on_network(session, %{
                         node_id: fixture["node_id"],
                         setup_pin: fixture["setup_pin"],
                         discriminator: fixture["discriminator"],
                         timeout: 60_000
                       })

              address = %{
                fabric_id: options[:fabric_id],
                node_id: fixture["node_id"],
                endpoint: 1,
                cluster: 6,
                member: 0
              }

              assert {:ok, %AttributeReport{value: %{type: :boolean, value: false}}} =
                       Matter.read_attribute(session, address)

              baseline = SoftwareResources.quiescent!(probe)
              subscription = subscribe!(session, address)
              assert :ok = SoftwarePeer.stop(first)
              {began, first_loss} = loss!(subscription.reference, 2)
              timer = timer!(probe, 1, 0)

              owned(fixture["peer"], 2, fn second ->
                recovered = recovered!(subscription.reference, 2, 1, began + 60_000)
                initial!(subscription.reference, recovered.sdk_subscription_id)
                restored = timer!(probe, 1, 1)
                assert :ok = SoftwarePeer.stop(second)
                {_began, second_loss} = loss!(subscription.reference, 3)
                cancelling = timer!(probe, 2, 1)
                started = now()
                assert :ok = Matter.unsubscribe(session, subscription)
                assert now() - started <= 1_000
                cancelled = SoftwareResources.quiescent!(probe, baseline)

                assert cancelled["objects"]["recovery_timer"] == %{
                         "acquired" => 2,
                         "destroyed" => 2
                       }

                reference = subscription.reference
                refute_receive {:wotex_matter, ^reference, _}, 50

                owned(fixture["peer"], 3, fn third ->
                  assert {:ok, %AttributeReport{}} = Matter.read_attribute(session, address)
                  fresh = subscribe!(session, address)
                  assert :ok = SoftwarePeer.stop(third)
                  {expiring, third_loss} = loss!(fresh.reference, 2)
                  active = timer!(probe, 3, 2)
                  attempts = expired!(fresh.reference, 2, 1, expiring + 60_000)
                  elapsed = now() - expiring
                  assert elapsed <= 61_000
                  expired = SoftwareResources.quiescent!(probe, baseline)

                  assert expired["objects"]["recovery_timer"] == %{
                           "acquired" => 3,
                           "destroyed" => 3
                         }

                  assert :ok = Matter.unsubscribe(session, fresh)
                  reference = fresh.reference
                  refute_receive {:wotex_matter, ^reference, _}, 50
                  shared = shared_recovery!(session, address, baseline, probe, fixture)

                  %{
                    baseline: baseline,
                    first_loss: first_loss,
                    timer: timer,
                    recovered: recovered,
                    restored: restored,
                    second_loss: second_loss,
                    cancelling: cancelling,
                    cancelled: cancelled,
                    third_loss: third_loss,
                    expiring: active,
                    expired: expired,
                    expiry_ms: elapsed,
                    attempts: attempts,
                    shared: shared
                  }
                end)
              end)
            end)

          %{status: "passed", observations: observations}
        after
          assert :ok = Matter.disconnect(session)
          refute Process.alive?(session.handle.pid)
          assert Port.info(port) == nil
          refute File.exists?("/proc/#{child}")
          SoftwareResources.final!(probe)
        end
      end)

    File.write!(fixture["result_path"], Jason.encode!(result), [:exclusive])
  end

  defp shared_recovery!(session, address, baseline, probe, fixture) do
    owned(fixture["peer"], 4, fn peer ->
      first = subscribe!(session, address)
      second = subscribe!(session, address)
      assert :ok = SoftwarePeer.stop(peer)
      {_first_started, _first_loss} = loss!(first.reference, 2)
      {second_started, _second_loss} = loss!(second.reference, 2)
      both = timer!(probe, 5, 3)
      assert :ok = Matter.unsubscribe(session, first)
      retained = timer!(probe, 5, 4)

      owned(fixture["peer"], 5, fn _ ->
        restored = recovered!(second.reference, 2, 1, second_started + 60_000)
        initial!(second.reference, restored.sdk_subscription_id)
        recovered = timer!(probe, 5, 5)
        assert :ok = Matter.unsubscribe(session, second)
        final = SoftwareResources.quiescent!(probe, baseline)
        %{both: both, retained: retained, restored: restored, recovered: recovered, final: final}
      end)
    end)
  end

  defp owned(descriptor, serial, callback) do
    assert {:ok, peer} =
             SoftwarePeer.start(descriptor["executable"], descriptor["arguments"],
               cd: descriptor["directory"],
               startup_timeout: 30_000,
               timeout: 300_000,
               ready: "Server Listening...",
               log: Path.join(descriptor["directory"], "peer-#{serial}.log")
             )

    try do
      callback.(peer)
    after
      if Process.alive?(peer.command.pid), do: assert(:ok = SoftwarePeer.stop(peer))
      assert Port.info(peer.port) == nil
      refute File.exists?("/proc/#{peer.os_pid}")
    end
  end

  defp subscribe!(session, address) do
    assert {:ok, subscription} =
             Matter.subscribe(session, %{
               kind: :attribute,
               paths: [address],
               receiver: self(),
               min_interval_s: 0,
               max_interval_s: 1,
               resubscribe: true
             })

    initial!(subscription.reference, nil)
    subscription
  end

  defp initial!(reference, sdk_id) do
    assert_receive {:wotex_matter, ^reference,
                    {:ok, %{type: :boolean, value: false}, %{initial: true} = metadata}},
                   3_000

    assert is_integer(metadata.sdk_subscription_id)
    if sdk_id, do: assert(metadata.sdk_subscription_id == sdk_id)
  end

  defp loss!(reference, generation), do: loss_until!(reference, generation, now() + 30_000)

  defp loss_until!(reference, generation, deadline) do
    receive do
      {:wotex_matter, ^reference,
       {:status, :resubscribing,
        %{generation: ^generation, continuity: :lost, attempt: 1} = metadata}} ->
        {now(), metadata}

      {:wotex_matter, ^reference, {:ok, %{type: :boolean, value: false}, %{initial: false}}} ->
        loss_until!(reference, generation, deadline)

      {:wotex_matter, ^reference, other} ->
        flunk("unexpected loss delivery: #{inspect(other)}")
    after
      max(0, deadline - now()) -> flunk("SDK did not enter recovery within 30 seconds")
    end
  end

  defp recovered!(reference, generation, attempt, deadline) do
    receive do
      {:wotex_matter, ^reference,
       {:status, :resubscribing, %{generation: ^generation, continuity: :lost, attempt: next}}} ->
        assert next == attempt + 1 and next <= 5
        recovered!(reference, generation, next, deadline)

      {:wotex_matter, ^reference,
       {:status, :resubscribed,
        %{generation: ^generation, continuity: :unknown, attempt: ^attempt} = metadata}} ->
        metadata

      {:wotex_matter, ^reference, other} ->
        flunk("unexpected recovery delivery: #{inspect(other)}")
    after
      max(0, deadline - now()) -> flunk("SDK did not recover within 60 seconds")
    end
  end

  defp expired!(reference, generation, attempt, deadline) do
    receive do
      {:wotex_matter, ^reference,
       {:status, :resubscribing, %{generation: ^generation, continuity: :lost, attempt: next}}} ->
        assert next == attempt + 1 and next <= 5
        expired!(reference, generation, next, deadline)

      {:wotex_matter, ^reference, {:error, %Error{code: :session_lost}}} ->
        attempt

      {:wotex_matter, ^reference, other} ->
        flunk("unexpected expiry delivery: #{inspect(other)}")
    after
      max(0, deadline + 1_000 - now()) ->
        flunk("SDK recovery exceeded 60 seconds plus cleanup allowance")
    end
  end

  defp timer!(probe, acquired, destroyed) do
    snapshot = SoftwareResources.snapshot!(probe, now() + 1_000)["native"]

    assert snapshot["objects"]["recovery_timer"] == %{
             "acquired" => acquired,
             "destroyed" => destroyed
           }

    snapshot
  end

  defp now, do: SoftwareResources.now()
end
