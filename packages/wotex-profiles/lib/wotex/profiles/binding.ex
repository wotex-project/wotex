defmodule Wotex.Profiles.Binding do
  @moduledoc """
  An explicit installed selector, operation and raw-value contract registration.

  Digest verification establishes immutable correspondence to this registration,
  not decoder correctness or device qualification. No reference selects a module,
  starts a transport or supplies an instance route.
  """

  alias Wotex.Profiles.{Error, Grammar, Schema}

  @fields ~w(id version selector_schema operations capture_fields raw_value_contract raw_value_schema codec_contracts)
  @operations Enum.map(Wotex.Runtime.operations(), &Atom.to_string/1)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Computes the exact installed registration identity from the closed map without sha256."
  @spec digest(term(), term()) :: {:ok, String.t()} | {:error, Error.t()}
  def digest(data, limits) do
    with {:ok, data, limits} <- Grammar.admit(data, limits),
         :ok <- validate(data, limits) do
      Grammar.identity("wotex.profile.binding@1", data, limits)
    end
  end

  @doc "Revalidates a complete registration and refuses a stale or forged digest."
  @spec new(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{data: data} = value, limits) when map_size(value) == 2, do: new(data, limits)

  def new(data, limits) do
    with {:ok, data, limits} <- Grammar.admit(data, limits),
         :ok <- Grammar.fields(data, ["sha256" | @fields], "/binding"),
         :ok <- Grammar.digest(data["sha256"], "/binding/sha256"),
         {:ok, identity} <- digest(Map.delete(data, "sha256"), limits),
         true <- data["sha256"] == identity do
      {:ok, %__MODULE__{data: data}}
    else
      false -> Error.refusal(:reference_conflict, "/binding/sha256")
      error -> error
    end
  end

  @doc "Returns checked installed registration data without resolving its references."
  @spec to_map(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value, limits) do
    with {:ok, checked} <- new(value, limits), do: {:ok, checked.data}
  end

  @doc "Returns the exact id, version and verified contract digest."
  @spec reference(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def reference(value, limits) do
    with {:ok, checked} <- new(value, limits),
         do: {:ok, Map.take(checked.data, ~w(id version sha256))}
  end

  defp validate(data, limits) do
    with :ok <- Grammar.fields(data, @fields, "/binding"),
         :ok <- Grammar.id(data["id"], "/binding/id"),
         :ok <- Grammar.version(data["version"], "/binding/version"),
         :ok <- Schema.check(data["selector_schema"], limits, "/binding/selector_schema"),
         true <- data["selector_schema"]["type"] == "object",
         :ok <- Schema.check(data["raw_value_schema"], limits, "/binding/raw_value_schema"),
         :ok <- operations(data["operations"]),
         :ok <- capture_fields(data["capture_fields"]),
         :ok <- Grammar.reference(data["raw_value_contract"], "/binding/raw_value_contract") do
      Grammar.references(data["codec_contracts"], limits, "/binding/codec_contracts")
    else
      false -> Error.refusal(:unsupported_selector, "/binding/selector_schema")
      error -> error
    end
  end

  defp operations(values) when is_list(values) and values != [] do
    if values == Enum.sort(Enum.uniq(values)) and Enum.all?(values, &(&1 in @operations)),
      do: :ok,
      else: Error.refusal(:unsupported_binding, "/binding/operations")
  end

  defp operations(_), do: Error.refusal(:unsupported_binding, "/binding/operations")

  defp capture_fields(values) when is_list(values) and length(values) <= 64 do
    with :ok <- Grammar.each(values, &Grammar.key(&1, "/binding/capture_fields")) do
      Grammar.sorted_unique(values, & &1, "/binding/capture_fields")
    end
  end

  defp capture_fields(_), do: Error.refusal(:input_limit, "/binding/capture_fields")
end
