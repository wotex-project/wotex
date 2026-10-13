defmodule Wotex.Routines.Continuum do
  @moduledoc "Lossless explicit Fact exchange through the existing Continuum observation extension."

  alias Wotex.Routines.{Error, Fact, Limits, Validation}
  alias WotexContinuum.ObservationProposal

  @extension "https://wotex.io/contracts/routines/fact/v1"
  @mapped ~w(id thing_id affordance_type affordance_name value source_time sequence quality)
  @extension_fields ~w(unit source_time_trust source_time_basis source_uncertainty_ms source_class source_id source_epoch received_at receipt_epoch receipt_ms
    profile_digest replay continuity expires_ms derivation_digest contributors)

  @doc "Builds an inert observation proposal from a complete fact and caller-supplied scope/evidence maps."
  @spec to_observation(Fact.t(), term(), term(), Limits.t()) ::
          {:ok, ObservationProposal.t()} | {:error, Error.t()}
  def to_observation(fact, scope, evidence, limits) do
    with {:ok, fact} <- Fact.new(fact, limits),
         {:ok, _, limits} <- Validation.admit([scope, evidence], limits, nil),
         :ok <- known_source_time(fact.data["source_time"]) do
      data = fact.data

      proposal = %{
        "proposal_id" => data["id"],
        "thing_id" => data["thing_id"],
        "affordance_type" => data["affordance_type"],
        "affordance_name" => data["affordance_name"],
        "value" => data["value"],
        "observed_at" => data["source_time"],
        "sequence" => data["sequence"],
        "quality" => %{"routine_quality" => data["quality"]},
        "context" => scope,
        "evidence" => evidence,
        "extensions" => %{@extension => Map.drop(data, @mapped)}
      }

      with :ok <- Validation.bounded(proposal, limits),
           {:ok, value} <- observation(proposal),
           :ok <- Validation.bounded(ObservationProposal.to_map(value), limits) do
        {:ok, value}
      end
    end
  end

  @doc "Reconstructs a complete Fact from bounded Continuum wire data; missing required semantics refuse."
  @spec from_observation(term(), Limits.t()) :: {:ok, Fact.t()} | {:error, Error.t()}
  def from_observation(input, limits) do
    with {:ok, input, limits} <- Validation.admit(input, limits, nil),
         {:ok, observation} <- observation(input),
         {:ok, quality} <- quality(observation.quality),
         extension when is_map(extension) <- observation.extensions[@extension],
         sequence when is_integer(sequence) <- observation.sequence do
      data =
        Map.merge(extension, %{
          "id" => observation.proposal_id,
          "thing_id" => observation.thing_id,
          "affordance_type" => Atom.to_string(observation.affordance_type),
          "affordance_name" => observation.affordance_name,
          "value" => observation.value,
          "source_time" => observation.observed_at,
          "sequence" => sequence,
          "quality" => quality
        })

      with :ok <- Validation.fields(extension, @extension_fields) do
        Fact.new(data, limits)
      end
    else
      {:error, _} = error -> error
      _ -> Error.refusal(:missing_exchange_semantics, "/extensions")
    end
  end

  defp observation(data) do
    case ObservationProposal.new(data) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> Error.refusal(:invalid_continuum_value)
    end
  end

  defp quality(%{"routine_quality" => value} = quality) when map_size(quality) == 1 do
    with :ok <- Validation.choice(value, ~w(usable stale invalid unknown), "/quality") do
      {:ok, value}
    end
  end

  defp quality(_), do: Error.refusal(:unsupported_quality, "/quality")

  defp known_source_time(nil), do: Error.refusal(:missing_source_time, "/source_time")
  defp known_source_time(_), do: :ok
end
