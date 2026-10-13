defmodule Wotex.Routines.AnalysisProfile do
  @moduledoc false

  alias Wotex.Routines.Error

  @proposal %{
    module: "ROUTINE-PROPOSAL-PREFIX",
    initial: "state(fresh, 0)",
    depth: 2,
    solutions: 4,
    transitions: 5,
    states: MapSet.new(["state(fresh,0)", "state(proposed,1)", "state(cancelled,1)"])
  }
  @receipt %{
    module: "ROUTINE-RECEIPT-PREFIX",
    initial: "state(fresh, 0, 0, false, none, false)",
    depth: 5,
    solutions: 13,
    transitions: 37,
    states:
      MapSet.new([
        "state(fresh,0,0,false,none,false)",
        "state(proposed,1,0,false,none,false)",
        "state(reserved,1,1,false,none,false)",
        "state(handed,1,1,true,none,false)",
        "state(handed,1,1,true,ack,false)",
        "state(completed,1,1,true,match,true)",
        "state(refused,1,0,false,none,true)",
        "state(failed,1,1,true,none,true)",
        "state(unknown,1,1,true,none,true)",
        "state(unknown,1,1,true,ack,true)",
        "state(cancelled,1,0,false,none,true)",
        "state(cancelled,1,1,false,none,true)"
      ])
  }

  @doc false
  @spec select(map()) :: {:ok, map()} | {:error, Error.t()}
  def select(%{"scope" => %{"profile" => "proposal-prefix@1"}}), do: {:ok, @proposal}
  def select(%{"scope" => %{"profile" => "receipt-prefix@1"}}), do: {:ok, @receipt}
  def select(_), do: Error.refusal(:unsupported_analysis_scope)
end
