defmodule Wotex.BACnet.SoftwareFormatter do
  @moduledoc false

  use GenServer

  @impl GenServer
  def init(_), do: {:ok, {File.cwd!(), []}}

  @impl GenServer
  def handle_cast({:test_finished, test}, {root, cases}) do
    name = Atom.to_string(test.name)

    entry = %{
      name: name,
      requirement_ids:
        Enum.uniq(
          ~r/WBA-[A-Z]+(?:-[A-Z]+)?[0-9]+[a-z]?/
          |> Regex.scan(name)
          |> List.flatten()
          |> Enum.concat(Map.get(test.tags, :requirements, []))
        ),
      outcome: outcome(test.state),
      source: Path.relative_to(test.tags.file, root)
    }

    {:noreply, {root, [entry | cases]}}
  end

  def handle_cast({:suite_finished, _}, {root, cases}) do
    path = Path.join(System.fetch_env!("WOTEX_BACNET_RESULTS_DIR"), "test-results.json")

    File.write!(
      path,
      Jason.encode!(%{schema: "wotex.bacnet.exunit@1", cases: Enum.reverse(cases)}, pretty: true) <>
        "\n"
    )

    {:noreply, {root, cases}}
  end

  def handle_cast(_, cases), do: {:noreply, cases}

  defp outcome(nil), do: "passed"
  defp outcome({:failed, _}), do: "failed"
  defp outcome({:skipped, _}), do: "skipped"
  defp outcome({:excluded, _}), do: "excluded"
  defp outcome(_), do: "invalid"
end
