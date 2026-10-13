defmodule Wotex.Routines.Evaluation do
  @moduledoc "Pure root-condition evaluation over explicit complete snapshots and caller-owned time."

  alias Wotex.Routines.{
    Compiler,
    Error,
    Limits,
    ObservationView,
    PredicateMachine,
    Profile,
    Snapshot,
    Time
  }

  @doc "Revalidates all inputs and computes only true, false or unknown; no trigger or effect is admitted."
  @spec evaluate(term(), term(), term(), Profile.t(), Limits.t()) ::
          {:ok, boolean() | String.t()} | {:error, Error.t()}
  def evaluate(program, snapshot, time, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         {:ok, data} <- Compiler.to_map(program, profile, limits),
         {:ok, snapshot} <- Snapshot.new(snapshot, program, profile, limits),
         {:ok, time} <- Time.new(time, limits) do
      values = ObservationView.values(data, snapshot.data, time.data, limits)
      PredicateMachine.run(data["ir"]["condition"], values, profile, limits)
    end
  end
end
