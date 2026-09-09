defmodule Wotex.Lab.Runner.Recording do
  @moduledoc """
  The recorded input, seed, version and decision stream of one attempt.

  A recording names the attempt, scenario, definition id and revision, the
  effective seed, the Lab version, the ordered step events (step id, input
  digest, outcome and value digest) and the terminal outcome. `compare/2`
  checks a later recording of the same definition against it: equal logical
  results reproduce, a differing step is a divergence. Scheduling and wall
  timings are never part of the comparison, and a real network trace is not
  claimed deterministic merely because its seed repeats.
  """

  alias Wotex.Lab.Error

  @type event :: %{
          step: String.t(),
          input_digest: String.t(),
          outcome: :ok | :error,
          digest: String.t()
        }

  @type t :: %__MODULE__{
          schema_version: String.t(),
          attempt_id: String.t(),
          scenario_id: String.t(),
          definition_id: String.t(),
          revision: String.t(),
          seed: non_neg_integer(),
          lab_version: String.t(),
          events: [event()],
          outcome: atom(),
          forced: boolean()
        }

  @enforce_keys [
    :schema_version,
    :attempt_id,
    :scenario_id,
    :definition_id,
    :revision,
    :seed,
    :lab_version,
    :events,
    :outcome,
    :forced
  ]
  defstruct @enforce_keys

  @outcomes [:pass, :fail, :unsupported, :timeout, :cancelled, :error]

  @doc false
  @spec validate(t()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = recording) do
    if valid_recording?(recording),
      do: :ok,
      else: {:error, Error.new(:invalid_recording, :preflight, "recording fields are invalid")}
  end

  def validate(_),
    do: {:error, Error.new(:invalid_recording, :preflight, "recording is invalid")}

  defp valid_recording?(recording) do
    [
      recording.schema_version == "1.0.0",
      bounded_string?(recording.attempt_id),
      bounded_string?(recording.scenario_id),
      bounded_string?(recording.definition_id),
      bounded_string?(recording.revision),
      valid_seed?(recording.seed),
      bounded_string?(recording.lab_version),
      valid_events?(recording.events),
      recording.outcome in @outcomes,
      is_boolean(recording.forced)
    ]
    |> Enum.all?()
  end

  defp valid_seed?(seed), do: is_integer(seed) and seed in 0..4_294_967_295

  defp valid_events?(events) when is_list(events) and length(events) <= 100_000,
    do: Enum.all?(events, &valid_event?/1)

  defp valid_events?(_), do: false

  @doc "Compares a replay recording with the original."
  @spec compare(t(), t()) :: {:reproduced, non_neg_integer()} | {:diverged, map()}
  def compare(%__MODULE__{} = original, %__MODULE__{} = replay) do
    cond do
      original.definition_id != replay.definition_id or original.revision != replay.revision ->
        {:diverged, %{reason: :different_definition}}

      original.seed != replay.seed ->
        {:diverged, %{reason: :different_seed}}

      original.lab_version != replay.lab_version ->
        {:diverged, %{reason: :different_version}}

      original.outcome != replay.outcome ->
        {:diverged, %{reason: :different_outcome}}

      true ->
        events(original.events, replay.events, 0)
    end
  end

  defp events([], [], count), do: {:reproduced, count}
  defp events([a | rest_a], [b | rest_b], count) when a == b, do: events(rest_a, rest_b, count + 1)

  defp events([a | _], [b | _], count),
    do: {:diverged, %{reason: :step, index: count, original: a, replay: b}}

  defp events(a, b, count),
    do: {:diverged, %{reason: :length, index: count, original: length(a), replay: length(b)}}

  @doc "The JSON-compatible form."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = recording) do
    %{
      "schema_version" => recording.schema_version,
      "attempt_id" => recording.attempt_id,
      "scenario_id" => recording.scenario_id,
      "definition_id" => recording.definition_id,
      "revision" => recording.revision,
      "seed" => recording.seed,
      "lab_version" => recording.lab_version,
      "events" =>
        Enum.map(
          recording.events,
          &%{
            "step" => &1.step,
            "input_digest" => &1.input_digest,
            "outcome" => Atom.to_string(&1.outcome),
            "digest" => &1.digest
          }
        ),
      "outcome" => Atom.to_string(recording.outcome),
      "forced" => recording.forced
    }
  end

  defp valid_event?(%{step: step, input_digest: input, outcome: outcome, digest: digest})
       when outcome in [:ok, :error],
       do: bounded_string?(step) and digest?(input) and digest?(digest)

  defp valid_event?(_), do: false

  defp bounded_string?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)

  defp digest?(value),
    do: is_binary(value) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, value)
end
