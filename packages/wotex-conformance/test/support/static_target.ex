defmodule Wotex.Conformance.StaticTarget do
  @moduledoc false

  @behaviour Wotex.Conformance.Target

  alias Wotex.Conformance.Target.Response

  @impl Wotex.Conformance.Target
  def artifact_path(%{artifact_path: path}), do: {:ok, path}

  @impl Wotex.Conformance.Target
  def invoke(%{actual: actual, owner: owner}, request) do
    send(owner, {:target_request, request})

    response = %Response{
      vector_id: request["vector"]["id"],
      outcome: :observed,
      actual: actual,
      codes: []
    }

    {:ok, response, 0}
  end
end
