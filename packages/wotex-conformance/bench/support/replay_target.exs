defmodule Wotex.Conformance.Bench.ReplayTarget do
  @moduledoc false

  # In-memory target adapter that answers each request with the observation
  # recorded for its vector, through the same response validation an external
  # target's output receives. It measures the runner without an external
  # process; a replayed observation is not evidence about any subject.

  @behaviour Wotex.Conformance.Target

  alias Wotex.Conformance.Corpus
  alias Wotex.Conformance.Target.Response

  @spec new(Corpus.t(), Path.t()) :: {module(), map()}
  def new(%Corpus{vectors: vectors}, artifact_path) do
    observations = Map.new(vectors, &{&1.id, &1.expectation.value})
    {__MODULE__, %{artifact_path: artifact_path, observations: observations}}
  end

  @impl Wotex.Conformance.Target
  @spec artifact_path(map()) :: {:ok, Path.t()}
  def artifact_path(%{artifact_path: path}), do: {:ok, path}

  @impl Wotex.Conformance.Target
  @spec invoke(map(), map()) ::
          {:ok, Response.t(), 0} | {:error, Wotex.Conformance.Error.t(), 0}
  def invoke(%{observations: observations}, %{"vector" => %{"id" => id}}) do
    reply = %{
      "protocol" => "wotex.conformance.target",
      "protocol_version" => "1.0",
      "vector_id" => id,
      "outcome" => "observed",
      "actual" => Map.fetch!(observations, id)
    }

    case Response.from_map(reply, id) do
      {:ok, response} -> {:ok, response, 0}
      {:error, error} -> {:error, error, 0}
    end
  end
end
