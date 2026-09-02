defmodule WotexContinuum do
  @moduledoc """
  Entry point for host-neutral continuum values.

  Values are inert data. `from_map/1` validates a decoded map and `to_map/1`
  returns its wire representation without performing I/O or host decisions.
  """

  alias WotexContinuum.{
    ActionIntent,
    ActionResult,
    Capability,
    Compatibility,
    Degradation,
    Delivery,
    EvidenceReference,
    ExecutionContext,
    ExitReceipt,
    Lifecycle,
    Manifest,
    Mode,
    ObservationProposal
  }

  @schema_version "1.0.0"
  @modules [
    Manifest,
    Compatibility,
    ExecutionContext,
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
  def kinds, do: @modules_by_kind |> Map.keys() |> Enum.sort()

  @doc "Constructs a registered value from a string-keyed or atom-keyed map."
  @spec from_map(map()) :: {:ok, struct()} | {:error, WotexContinuum.Error.t()}
  def from_map(data) when is_map(data) do
    with {:ok, kind} <- fetch_discriminator(data),
         {:ok, module} <- module_for_kind(kind) do
      module.new(data)
    end
  end

  def from_map(_data), do: WotexContinuum.Error.error(:invalid_type, [], "expected an object")

  @doc "Returns the string-keyed wire map for a registered value."
  @spec to_map(struct()) :: {:ok, map()} | {:error, WotexContinuum.Error.t()}
  def to_map(%module{} = value) when module in @modules, do: {:ok, module.to_map(value)}

  def to_map(_value) do
    WotexContinuum.Error.error(:unsupported_value, [], "expected a registered continuum value")
  end

  @doc false
  @spec module_for_kind(String.t()) :: {:ok, module()} | {:error, WotexContinuum.Error.t()}
  def module_for_kind(kind) when is_binary(kind) do
    case Map.fetch(@modules_by_kind, kind) do
      {:ok, module} -> {:ok, module}
      :error -> WotexContinuum.Error.error(:unknown_kind, ["kind"], "unknown continuum kind")
    end
  end

  def module_for_kind(_kind) do
    WotexContinuum.Error.error(:invalid_type, ["kind"], "expected a string")
  end

  defp fetch_discriminator(data) do
    string_value = Map.get(data, "kind", :missing)
    atom_value = Map.get(data, :kind, :missing)

    case {string_value, atom_value} do
      {:missing, :missing} ->
        WotexContinuum.Error.error(:required, ["kind"], "field is required")

      {value, :missing} ->
        validate_discriminator(value)

      {:missing, value} ->
        validate_discriminator(value)

      {_left, _right} ->
        WotexContinuum.Error.error(:duplicate_field, ["kind"], "field appears more than once")
    end
  end

  defp validate_discriminator(value) when is_binary(value), do: {:ok, value}

  defp validate_discriminator(_value) do
    WotexContinuum.Error.error(:invalid_type, ["kind"], "expected a string")
  end
end
