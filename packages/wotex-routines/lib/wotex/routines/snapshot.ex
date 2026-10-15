defmodule Wotex.Routines.Snapshot do
  @moduledoc """
  Validates the complete immutable input snapshot for a compiled routine.

  `new/4` takes snapshot data, the program, `Wotex.Routines.Profile` and
  `Wotex.Routines.Limits`, returning `{:ok, snapshot}` or `{:error, error}` with
  a `Wotex.Routines.Error`. `to_map/4` repeats validation before returning the
  complete data map. The program is regenerated before snapshot correspondence
  is checked.

  Required fields are `"id"`, `"membership_generation"`, `"active_programs"`,
  `"resource_revisions"`, `"binding_bases"` and `"facts"`. Active programs are
  distinct IR digests within the selected definition bound. Revisions must cover
  every compiled Thing and resource role. Both binding maps must contain exactly
  the compiled binding names, with an explicit `nil` fact for each absent input.

  Each binding basis supplies its installed profile digest, expected source
  identity/epoch and optional source-clock basis. Each non-null fact must be a
  complete `Wotex.Routines.Fact`; its presence does not make it usable. Evaluation
  separately checks identity, quality, continuity, receipt freshness and any
  required source-time confidence against the supplied time. Stale facts remain
  data and cannot replace the expected binding basis.

  The consumer owns atomic collection and current membership/resource checks.
  Constructing a snapshot does not prove that its generations, observations or
  active set describe current authority, nor does it admit an effect.
  """

  alias Wotex.Routines.{Compiler, Error, Fact, Limits, Profile, Validation}

  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @fields ~w(id membership_generation active_programs resource_revisions binding_bases facts)
  @basis_fields ~w(profile_digest source_id source_epoch source_time_basis)

  @doc "Checks complete binding/resource coverage and facts against a current Program."
  @spec new(term(), term(), Profile.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, program, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <- Validation.fields(data, @fields),
         :ok <- Validation.text(data["id"], "/id"),
         :ok <- Validation.text(data["membership_generation"], "/membership_generation"),
         :ok <- Validation.strings(data["active_programs"], "/active_programs"),
         :ok <- active_bound(data["active_programs"], profile),
         :ok <- Validation.each(data["active_programs"], &Validation.digest(&1, "/active_programs")),
         :ok <- resources(data["resource_revisions"], program, limits),
         :ok <- binding_bases(data["binding_bases"], program),
         :ok <- facts(data["facts"], Map.keys(program["context"]["bindings"]), limits) do
      {:ok, %__MODULE__{data: data}}
    end
  end

  defp active_bound(programs, profile) do
    if length(programs) <= profile.data["active_definitions"],
      do: :ok,
      else: Error.refusal(:definition_bound, "/active_programs")
  end

  @doc "Revalidates a complete snapshot before projection."
  @spec to_map(term(), term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(snapshot, program, profile, limits) do
    with {:ok, snapshot} <- new(snapshot, program, profile, limits), do: {:ok, snapshot.data}
  end

  defp resources(data, program, limits) do
    names =
      program["context"]["bindings"]
      |> Map.values()
      |> Enum.flat_map(&[&1["thing_id"] | Map.values(&1["resource_roles"])])
      |> Enum.uniq()

    with :ok <- Validation.fields(data, names) do
      Validation.each(Map.values(data), &Validation.integer(&1, limits, "/resource_revisions", 0))
    end
  end

  defp binding_bases(data, program) do
    with :ok <- Validation.fields(data, Map.keys(program["context"]["bindings"])) do
      Validation.each(Map.to_list(data), &binding_basis(&1, program))
    end
  end

  defp binding_basis({name, basis}, program) do
    with :ok <- Validation.fields(basis, @basis_fields),
         :ok <- Validation.digest(basis["profile_digest"], "/binding_bases"),
         :ok <- Validation.text(basis["source_id"], "/binding_bases"),
         :ok <- Validation.text(basis["source_epoch"], "/binding_bases"),
         :ok <- optional_clock_basis(basis["source_time_basis"]) do
      expected = program["context"]["bindings"][name]["basis"]["semantic_digest"]
      if basis["profile_digest"] == expected, do: :ok, else: Error.refusal(:stale_binding_basis)
    end
  end

  defp optional_clock_basis(nil), do: :ok

  defp optional_clock_basis(digest),
    do: Validation.digest(digest, "/binding_bases/source_time_basis")

  defp facts(data, names, limits) do
    with :ok <- Validation.fields(data, names) do
      Validation.each(Map.values(data), fn
        nil ->
          :ok

        value ->
          case Fact.new(value, limits) do
            {:ok, _} -> :ok
            error -> error
          end
      end)
    end
  end
end
