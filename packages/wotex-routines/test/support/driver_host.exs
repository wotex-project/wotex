defmodule Wotex.Routines.TestDriverHost do
  @moduledoc false

  @behaviour Wotex.Routines.DriverHost

  @impl Wotex.Routines.DriverHost
  @spec wakeup(
          {pid(), term()},
          Wotex.Routines.DriverHost.cause(),
          Wotex.Routines.DriverHost.budget()
        ) :: :ok | {:error, atom()}
  def wakeup({owner, tag}, cause, budget) do
    send(owner, {tag, :entered, self(), cause, budget})
    await_signal()
  end

  defp await_signal do
    receive do
      {:probe, owner, reference} ->
        send(owner, {reference, :active})
        await_signal()

      :finish ->
        :ok

      :fail ->
        {:error, :host_failure}

      :raise ->
        raise "synthetic-private-context"

      :throw ->
        throw(:synthetic_private_context)

      :crash ->
        Process.exit(self(), :kill)
    end
  end
end
