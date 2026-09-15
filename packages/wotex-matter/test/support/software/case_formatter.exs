defmodule Wotex.Matter.SoftwareCaseFormatter do
  @moduledoc false

  use GenServer

  alias Wotex.Matter.SoftwareManifest

  @impl GenServer
  def init(options) do
    context = Keyword.fetch!(options, :software_acceptance)

    {:ok,
     %{
       context: context,
       seed: Keyword.fetch!(options, :seed),
       expected: MapSet.new(context.cases, &{&1["module"], &1["name"]}),
       observed: %{},
       duplicate: 0,
       unexpected: 0,
       failed: 0,
       hardware_executed: 0
     }}
  end

  @impl GenServer
  def handle_cast({:test_finished, test}, state) do
    identity = {Atom.to_string(test.module), Atom.to_string(test.name)}
    status = status(test.state)

    state =
      if status in ["failed", "invalid"], do: Map.update!(state, :failed, &(&1 + 1)), else: state

    state =
      if test.tags[:hardware] == true and status != "excluded",
        do: Map.update!(state, :hardware_executed, &(&1 + 1)),
        else: state

    state =
      cond do
        Map.has_key?(state.observed, identity) ->
          Map.update!(state, :duplicate, &(&1 + 1))

        MapSet.member?(state.expected, identity) ->
          put_in(state.observed[identity], status)

        test.tags[:software] ->
          Map.update!(state, :unexpected, &(&1 + 1))

        true ->
          state
      end

    {:noreply, state}
  end

  def handle_cast({:suite_finished, _times}, state) do
    cases =
      Enum.map(state.context.cases, fn item ->
        status = Map.get(state.observed, {item["module"], item["name"]}, "missing")
        Map.put(item, "status", status)
      end)

    completed_source = SoftwareManifest.identity(state.context.root)["source_sha256"]

    passed =
      Enum.all?(cases, &(&1["status"] == "passed")) and
        state.duplicate == 0 and state.unexpected == 0 and state.failed == 0 and
        state.hardware_executed == 0 and completed_source == state.context.source_sha256

    result = %{
      schema: "wotex.matter.software-results@1",
      status: if(passed, do: "passed", else: "failed"),
      source_sha256: state.context.source_sha256,
      completed_source_sha256: completed_source,
      inventory_sha256: state.context.inventory_sha256,
      elixir: System.version(),
      otp: otp_version(),
      seed: state.seed,
      cases: cases,
      duplicate: state.duplicate,
      unexpected: state.unexpected,
      failed: state.failed,
      hardware_executed: state.hardware_executed
    }

    path = state.context.result
    {:ok, file} = File.open(path, [:write, :exclusive])

    try do
      File.chmod!(path, 0o600)
      IO.binwrite(file, Jason.encode!(result, pretty: true) <> "\n")
    after
      File.close(file)
    end

    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  defp status(nil), do: "passed"
  defp status({:excluded, _}), do: "excluded"
  defp status({:skipped, _}), do: "skipped"
  defp status({:failed, _}), do: "failed"
  defp status(_), do: "invalid"

  defp otp_version do
    :code.root_dir()
    |> List.to_string()
    |> Path.join("releases/#{System.otp_release()}/OTP_VERSION")
    |> File.read!()
    |> String.trim()
  end
end
