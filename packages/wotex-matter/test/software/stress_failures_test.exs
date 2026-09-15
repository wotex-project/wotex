Code.require_file("../support/software/resources.exs", __DIR__)

defmodule Wotex.Matter.NativeStressFailuresTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Error, Native, SoftwareResources}

  @moduletag :software
  @moduletag :interop
  @moduletag timeout: 90_000

  test "WMA-C09 read load retains bounded cleanup after deadline, EOF and malformed native responses" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_STRESS_FAILURES_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    controller = fixture["controller"]

    options =
      [
        client: Native,
        lifecycle: :persistent,
        storage_mode: :open_existing,
        authority: :stored,
        timeout: 10_000
      ] ++
        Enum.map(
          ~w(executable storage_path vendor_id fabric_id controller_node_id paa_trust_store)a,
          &{&1, Map.fetch!(controller, Atom.to_string(&1))}
        )

    address = %{
      fabric_id: options[:fabric_id],
      node_id: fixture["node_id"],
      endpoint: fixture["endpoint"],
      cluster: 6,
      member: 0
    }

    observations =
      for {kind, code} <- [
            {"deadline", :timeout},
            {"eof", :transport_closed},
            {"malformed_response", :invalid_frame}
          ] do
        observation =
          SoftwareResources.with_probe(
            fixture["resource_directory"],
            %{"interaction_fault" => kind, "fault_after" => 101},
            fn probe ->
              assert {:ok, session} = Matter.connect(options)
              owner = session.handle.pid
              monitor = Process.monitor(owner)
              port = :sys.get_state(owner).port
              {:os_pid, child} = Port.info(port, :os_pid)

              try do
                values =
                  for _ <- 1..100 do
                    assert {:ok, %AttributeReport{value: value}} =
                             Matter.read_attribute(session, address)

                    value
                  end

                assert length(Enum.uniq(values)) == 1
                started = now()

                assert {:error, %Error{code: ^code, effect: :none}} =
                         Matter.read_attribute(session, address, timeout: 500)

                returned = now()
                assert returned - started <= 1_500
                assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 1_000
                assert gone?(port, child, returned + 1_000)
                assert :ets.info(session.handle.admission) == :undefined
                resource = SoftwareResources.fault!(probe, kind, 101, child)
                assert resource["native"]["objects"]["interaction"]["acquired"] == 101
                assert resource["native"]["objects"]["read_client"]["acquired"] == 101

                %{
                  kind: kind,
                  code: code,
                  completed_reads: 100,
                  request_ms: returned - started,
                  cleanup_ms: now() - returned,
                  resources: resource
                }
              after
                assert :ok = Matter.disconnect(session)
                assert gone?(port, child, now() + 1_000)
              end
            end
          )

        SoftwareResources.with_probe(fixture["resource_directory"], fn probe ->
          assert {:ok, session} = Matter.connect(options)

          try do
            assert {:ok, %AttributeReport{}} = Matter.read_attribute(session, address)
          after
            assert :ok = Matter.disconnect(session)
            SoftwareResources.final!(probe)
          end
        end)

        Map.put(observation, :store_reopened, true)
      end

    File.write!(
      fixture["result_path"],
      Jason.encode!(%{status: "passed", observations: observations}),
      [:exclusive]
    )
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
