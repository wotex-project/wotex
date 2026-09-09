defmodule Wotex.BLE.SoftwareFormatter do
  @moduledoc false

  use GenServer

  @impl GenServer
  def init(_), do: {:ok, []}

  @impl GenServer
  def handle_cast({:test_finished, test}, cases) do
    status =
      case test.state do
        nil -> :passed
        {:excluded, _} -> :excluded
        {:skipped, _} -> :skipped
        {:invalid, _} -> :invalid
        {:failed, _} -> :failed
      end

    entry = %{module: Atom.to_string(test.module), name: Atom.to_string(test.name), status: status}
    {:noreply, [entry | cases]}
  end

  def handle_cast({:suite_finished, _}, cases) do
    report = %{cases: Enum.reverse(cases), counts: Enum.frequencies_by(cases, & &1.status)}
    File.write!(System.fetch_env!("WOTEX_BLE_SOFTWARE_REPORT"), Jason.encode!(report) <> "\n")
    {:noreply, cases}
  end

  def handle_cast(_, cases), do: {:noreply, cases}
end
