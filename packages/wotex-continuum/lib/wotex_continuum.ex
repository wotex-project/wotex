defmodule WotexContinuum do
  @moduledoc """
  Entry point for host-neutral continuum values.

  Values are inert data. `from_map/1` validates a decoded map and `to_map/1`
  returns its wire representation without performing I/O or host decisions.

  `schema_version/0` identifies the common 2.0.0 envelope, and `kinds/0`
  returns the closed top-level kind registry in lexical order. `from_map/1`
  resolves that discriminator without creating atoms from input, then delegates
  to the owning value module. `to_map/1` revalidates registered structs before
  returning string-keyed JSON-compatible data.

  This facade selects the value constructor by kind and defines wire identity. It does not resolve a Thing,
  authorize or execute an Action, reconcile state, fetch evidence, deliver an
  item, or apply lifecycle changes to a runtime. Consumers retain those
  responsibilities and can use `WotexContinuum.Schema` for the embedded schema
  bytes that describe the accepted values.
  """

  alias WotexContinuum.{
    ActionIntent,
    ActionResult,
    Capability,
    Compatibility,
    Degradation,
    Delivery,
    EvidenceReference,
    ExecutionScope,
    ExitReceipt,
    Lifecycle,
    Manifest,
    Mode,
    ObservationProposal
  }

  @schema_version "2.0.0"
  @modules [
    Manifest,
    Compatibility,
    ExecutionScope,
    Capability,
    ObservationProposal,
    ActionIntent,
    ActionResult,
    EvidenceReference,
    Delivery,
    Mode,
    Lifecycle,
    Degradation,
    ExitReceipt
  ]
  @modules_by_kind Map.new(@modules, &{&1.kind(), &1})

  @doc "The current encoded contract version."
  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @doc "Returns every registered top-level kind in lexical order."
  @spec kinds() :: [String.t()]
  def kinds do
    @modules_by_kind
    |> Map.keys()
    |> Enum.sort()
  end

  @doc "Constructs a registered value from a string-keyed or atom-keyed map."
  @spec from_map(map()) :: {:ok, struct()} | {:error, WotexContinuum.Error.t()}
  def from_map(data) when is_map(data) do
    with {:ok, kind} <- fetch_discriminator(data),
         {:ok, module} <- module_for_kind(kind) do
      module.from_map(data)
    end
  end

  def from_map(_),
    do: WotexContinuum.Error.error(:invalid_type, :validation, "/", "expected an object")

  @doc "Returns the string-keyed wire map for a registered value."
  @spec to_map(struct()) :: {:ok, map()} | {:error, WotexContinuum.Error.t()}
  def to_map(%module{} = value) when module in @modules do
    with {:ok, validated} <- module.from_map(value) do
      {:ok, module.to_map(validated)}
    end
  end

  def to_map(_) do
    WotexContinuum.Error.error(
      :unsupported_value,
      :validation,
      "/",
      "expected a registered continuum value"
    )
  end

  @doc false
  @spec module_for_kind(String.t()) :: {:ok, module()} | {:error, WotexContinuum.Error.t()}
  def module_for_kind(kind) when is_binary(kind) do
    case Map.fetch(@modules_by_kind, kind) do
      {:ok, module} ->
        {:ok, module}

      :error ->
        WotexContinuum.Error.error(:unknown_kind, :validation, "/kind", "unknown continuum kind")
    end
  end

  def module_for_kind(_) do
    WotexContinuum.Error.error(:invalid_type, :validation, "/kind", "expected a string")
  end

  defp fetch_discriminator(data) do
    string_value = Map.get(data, "kind", :missing)
    atom_value = Map.get(data, :kind, :missing)

    case {string_value, atom_value} do
      {:missing, :missing} ->
        WotexContinuum.Error.error(:required, :validation, "/kind", "field is required")

      {value, :missing} ->
        validate_discriminator(value)

      {:missing, value} ->
        validate_discriminator(value)

      {_, _} ->
        WotexContinuum.Error.error(
          :duplicate_field,
          :validation,
          "/kind",
          "field appears more than once"
        )
    end
  end

  defp validate_discriminator(value) when is_binary(value), do: {:ok, value}

  defp validate_discriminator(_) do
    WotexContinuum.Error.error(:invalid_type, :validation, "/kind", "expected a string")
  end
end
