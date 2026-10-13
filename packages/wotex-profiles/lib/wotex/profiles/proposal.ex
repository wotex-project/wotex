defmodule Wotex.Profiles.Proposal do
  @moduledoc """
  A bounded inert interpretation proposal retaining complete reader provenance.

  Construction checks representation and explicit limits. It does not establish
  producer custody, semantic correspondence, source trust or consumer admission.
  """

  alias Wotex.Profiles.{Error, Grammar, Limits, Report, Unit}

  @fields ~w(channel_id affordance semantic unit normalized_value quality quality_reason continuity source_ref source_epoch sequence source_time receipt_time profile_sha256 closure_sha256 capture_digest compiler_ref interpretation)
  @contract Path.expand("../../../priv/contracts/proposal.json", __DIR__)
  @external_resource @contract
  @manifest Jason.decode!(File.read!(@contract))
  {:ok, manifest_bytes} = Wotex.JSON.encode(@manifest)

  @identity %{
    "id" => "urn:wotex:profiles:proposal",
    "version" => "1.0.0",
    "sha256" => Grammar.hash("wotex.profile.proposal-contract@1\n" <> manifest_bytes)
  }
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Returns the installed representation-contract identity, separate from artifact custody."
  @spec identity() :: %{String.t() => String.t()}
  def identity, do: @identity

  @doc "Revalidates a complete proposal map or exact native value under explicit limits."
  @spec new(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{data: data} = value, limits) when map_size(value) == 2,
    do: new(data, limits)

  def new(data, limits) do
    with {:ok, data, _} <- Grammar.admit(data, limits),
         :ok <- Grammar.fields(data, @fields, "/proposal"),
         :ok <- Report.provenance(data),
         :ok <- affordance(data["affordance"]),
         :ok <- Grammar.reference(data["semantic"], "/proposal/semantic"),
         :ok <- Grammar.reference(data["compiler_ref"], "/proposal/compiler_ref"),
         :ok <- Grammar.digest(data["closure_sha256"], "/proposal/closure_sha256"),
         :ok <- Grammar.digest(data["capture_digest"], "/proposal/capture_digest"),
         :ok <- unit(data["unit"], limits),
         {:ok, value} <- Wotex.Runtime.Codec.Value.validate(data["normalized_value"]),
         true <- data["interpretation"] in ~w(profile_declared unconverted),
         true <- quality(data, value) do
      {:ok, %__MODULE__{data: data}}
    else
      {:error, %Error{} = error} -> {:error, proposal_path(error)}
      _ -> Error.refusal(:invalid_input, "/proposal")
    end
  end

  @doc "Revalidates and returns all proposal members without inferring missing provenance."
  @spec to_map(term(), Limits.t() | map()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value, limits) do
    with {:ok, checked} <- new(value, limits), do: {:ok, checked.data}
  end

  defp affordance(data) do
    with :ok <- Grammar.fields(data, ~w(kind name), "/proposal/affordance"),
         true <- data["kind"] in ~w(property action event),
         :ok <- Grammar.key(data["name"], "/proposal/affordance/name"),
         do: :ok,
         else: (_ -> Error.refusal(:invalid_input, "/proposal/affordance"))
  end

  defp unit(nil, _), do: :ok

  defp unit(data, limits) do
    with {:ok, _} <- Unit.new(data, limits), do: :ok
  end

  defp quality(%{"quality" => "usable"}, value), do: value["type"] != "null"

  defp quality(data, value),
    do: value == %{"type" => "null"} and data["interpretation"] == "unconverted"

  defp proposal_path(%Error{path: "/report" <> suffix} = error),
    do: %{error | path: "/proposal" <> suffix}

  defp proposal_path(error), do: error
end
