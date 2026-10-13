defmodule Wotex.Profiles.Capture do
  @moduledoc """
  Supplied immutable capture fields tied to one installed binding and epoch.

  A verified digest checks internal correspondence, not source authenticity,
  model truth, current enrollment or physical qualification. No device is read.
  """

  alias Wotex.Profiles.{Binding, Error, Grammar}

  @fields ~w(binding capture_epoch fields)
  @types ~w(boolean text sint uint)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Computes the exact capture digest from its closed three-field map."
  @spec digest(term(), term(), term()) :: {:ok, String.t()} | {:error, Error.t()}
  def digest(data, binding, limits) do
    with {:ok, data, limits} <- Grammar.admit(data, limits),
         {:ok, binding} <- Binding.new(binding, limits),
         :ok <- validate(data, binding) do
      {:ok, bytes} = Wotex.JSON.encode(data, Grammar.options(limits))
      {:ok, Grammar.hash(bytes)}
    end
  end

  @doc "Revalidates the complete capture and refuses changed or forged identity."
  @spec new(term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{data: data} = value, binding, limits) when map_size(value) == 2,
    do: new(data, binding, limits)

  def new(data, binding, limits) do
    with {:ok, data, limits} <- Grammar.admit(data, limits),
         :ok <- Grammar.fields(data, ["digest" | @fields], "/capture"),
         :ok <- Grammar.digest(data["digest"], "/capture/digest"),
         {:ok, identity} <- digest(Map.delete(data, "digest"), binding, limits),
         true <- identity == data["digest"] do
      {:ok, %__MODULE__{data: data}}
    else
      false -> Error.refusal(:stale_basis, "/capture/digest")
      error -> error
    end
  end

  @doc "Returns checked capture data under the explicit selected binding and limits."
  @spec to_map(term(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value, binding, limits) do
    with {:ok, checked} <- new(value, binding, limits), do: {:ok, checked.data}
  end

  defp validate(data, binding) do
    with :ok <- Grammar.fields(data, @fields, "/capture"),
         :ok <- Grammar.reference(data["binding"], "/capture/binding"),
         true <- data["binding"] == Map.take(binding.data, ~w(id version sha256)),
         :ok <- epoch(data["capture_epoch"]),
         :ok <-
           Grammar.fields(data["fields"], [], "/capture/fields", binding.data["capture_fields"]) do
      Grammar.each(Map.values(data["fields"]), &Grammar.scalar(&1, @types, "/capture/fields"))
    else
      false -> Error.refusal(:stale_basis, "/capture/binding")
      error -> error
    end
  end

  defp epoch(value) do
    if is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value),
      do: :ok,
      else: Error.refusal(:invalid_input, "/capture/capture_epoch")
  end
end
