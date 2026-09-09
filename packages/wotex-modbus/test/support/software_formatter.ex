defmodule Wotex.Modbus.SoftwareFormatter do
  @moduledoc false

  use GenServer

  @impl GenServer
  def init(_), do: {:ok, []}

  @impl GenServer
  def handle_cast({:test_finished, test}, cases) do
    name = Atom.to_string(test.name)

    entry = %{
      name: name,
      requirement_ids:
        ~r/WMB-[A-Z]+(?:-[A-Z]+)?[0-9]+/
        |> Regex.scan(name)
        |> List.flatten()
        |> Enum.uniq(),
      outcome: outcome(test.state),
      source: Path.relative_to(test.tags.file, File.cwd!())
    }

    {:noreply, [entry | cases]}
  end

  def handle_cast({:suite_finished, _}, cases) do
    path = Path.join(System.fetch_env!("WOTEX_MODBUS_SOFTWARE_EVIDENCE"), "test-results.json")

    File.write!(
      path,
      Jason.encode!(%{schema: "wotex.modbus.exunit@1", cases: Enum.reverse(cases)}, pretty: true) <>
        "\n"
    )

    {:noreply, cases}
  end

  def handle_cast(_, cases), do: {:noreply, cases}

  defp outcome(nil), do: "passed"
  defp outcome({:failed, _}), do: "failed"
  defp outcome({:skipped, _}), do: "skipped"
  defp outcome({:excluded, _}), do: "excluded"
  defp outcome(_), do: "invalid"
end
