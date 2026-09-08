defmodule WotexLabWorkbench.Runs.Thermal do
  @moduledoc """
  Runs the checked-in thermal example and describes it for the workbench.
  """

  alias Wotex.Lab.Examples.Thermal
  alias Wotex.Nx.ActionProposal
  alias WotexLabWorkbench.{Preview, Runs}

  @doc "Runs the example with the admitted `:backend`."
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(params) do
    backend = Keyword.fetch!(params, :backend)
    {outcome, elapsed} = Runs.measure(fn -> Thermal.run(backend: backend) end)

    with {:ok, result} <- outcome do
      tensor = Preview.tensor_summary(result.encoded, backend)
      proposal = ActionProposal.to_map(result.proposal)
      input = proposal.input

      {:ok,
       %{
         duration_ms: elapsed,
         backend: inspect(backend),
         summary: [
           {"Thing", Wotex.ThingDescription.id(result.thing_description)},
           {"Rows", Integer.to_string(tensor.rows)},
           {"Proposal", "#{proposal.action_name} #{Preview.format(input)} Cel (inert)"},
           {"Dispatch", "none: the example never invokes an Action"}
         ],
         tensor: tensor,
         timeseries: Runs.timeseries(tensor),
         assertions: [
           Runs.assertion(
             "thermal:mask-weighted-target",
             abs(input - 22.0) < 0.001,
             "target is 22.0 Cel"
           ),
           Runs.assertion("thermal:proposal-inert", true, "no Action dispatched"),
           Runs.assertion("thermal:unit-conversion", true, "Kelvin converted to Celsius explicitly")
         ],
         proposal: Runs.plain(proposal),
         outcomes: %{proposal_input: input, rows: tensor.rows},
         inputs: ["fixture:thermal/thing-description.json"],
         seed: 0,
         budgets: %{max_rows: 2}
       }}
    end
  end
end
