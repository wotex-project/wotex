defmodule Wotex.Thread.SoftwareCases do
  @moduledoc false

  # Records one JSON line per executed ExUnit case for the explicit software runner.
  use GenServer

  @impl GenServer
  def init(_) do
    path = System.fetch_env!("WOTEX_THREAD_CASE_RESULTS")
    {:ok, file} = File.open(path, [:write, :exclusive, :utf8])
    {:ok, file}
  end

  @impl GenServer
  def handle_cast({:test_finished, %ExUnit.Test{state: {:excluded, _}}}, file),
    do: {:noreply, file}

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, file) do
    state =
      case test.state do
        nil -> "passed"
        {:failed, _} -> "failed"
        {:skipped, _} -> "skipped"
        {:invalid, _} -> "invalid"
      end

    line = %{
      "module" => inspect(test.module),
      "name" => Atom.to_string(test.name),
      "state" => state
    }

    IO.write(file, Jason.encode!(line) <> "\n")
    {:noreply, file}
  end

  def handle_cast({:suite_finished, _}, file) do
    File.close(file)
    {:noreply, nil}
  end

  def handle_cast(_, file), do: {:noreply, file}
end
