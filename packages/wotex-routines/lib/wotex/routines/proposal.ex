defmodule Wotex.Routines.Proposal do
  @moduledoc false

  alias Wotex.Routines.ExecutionTree

  @doc false
  @spec from_step(map(), map(), map(), map()) :: map()
  def from_step(program, run, node, record) do
    binding = program["context"]["bindings"][node["binding"]]
    basis = ExecutionTree.basis(program, node)

    %{
      "original" => run["original"],
      "step_original" => record["original"],
      "program_digest" => program["ir_digest"],
      "path" => node["path"],
      "binding" => node["binding"],
      "installed_basis" => binding["basis"],
      "thing_id" => binding["thing_id"],
      "resource_roles" => binding["resource_roles"],
      "resource_domains" => domains(binding),
      "operation" => basis["affordance"]["operation"],
      "input" => node["input"],
      "completion" => node["completion"],
      "evidence_contract" => node["evidence_contract"]
    }
  end

  defp domains(binding) do
    [binding["thing_id"] | Map.values(binding["resource_roles"])]
    |> Enum.uniq()
    |> Enum.sort()
  end
end
