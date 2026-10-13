defmodule Wotex.Routines.Registry do
  @moduledoc "Caller-supplied immutable offline contract closure. No code, fetch or registration occurs."

  alias Wotex.Routines.{Error, Limits, Validation}

  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: [map()]}

  @doc "Validates exact identities, unique IDs, complete imports and an acyclic closure."
  @spec new(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, limits) do
    with {:ok, data, _} <- Validation.admit(input, limits, __MODULE__),
         :ok <- Validation.each(data, &record/1),
         :ok <- unique(data),
         table = Map.new(data, &{&1["id"], &1}),
         :ok <- references(data, table),
         :ok <- acyclic(table) do
      {:ok, %__MODULE__{data: Enum.sort_by(data, & &1["id"])}}
    end
  end

  @doc "Checks one closed exact reference against the supplied registry."
  @spec require_contract(t(), term(), Limits.t()) :: :ok | {:error, Error.t()}
  def require_contract(registry, ref, limits) do
    require_all(registry, [ref], limits)
  end

  @doc "Checks a finite set of exact references after one closure validation."
  @spec require_all(t(), term(), Limits.t()) :: :ok | {:error, Error.t()}
  def require_all(registry, refs, limits) do
    with {:ok, registry} <- new(registry, limits),
         {:ok, refs, _} <- Validation.admit(refs, limits, nil),
         :ok <- Validation.each(refs, &reference/1) do
      table = Map.new(registry.data, &{&1["id"], &1})
      Validation.each(refs, &require_ref(&1, table))
    end
  end

  @doc "Revalidates and projects the installed closure as finite JSON data."
  @spec to_map(term(), Limits.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def to_map(value, limits) do
    with {:ok, value} <- new(value, limits), do: {:ok, value.data}
  end

  defp record(data) do
    with :ok <- Validation.fields(data, ~w(id version semantic_digest requires)),
         :ok <- identity(data),
         :ok <- Validation.each(data["requires"], &reference/1) do
      distinct_imports(data["requires"])
    end
  end

  defp distinct_imports(refs) do
    ids = Enum.map(refs, & &1["id"])
    if Enum.uniq(ids) == ids, do: :ok, else: Error.refusal(:duplicate_identity, "/requires")
  end

  defp reference(data) do
    with :ok <- Validation.fields(data, ~w(id version semantic_digest)), do: identity(data)
  end

  defp identity(data) do
    with :ok <- Validation.text(data["id"], "/id"),
         :ok <- Validation.text(data["version"], "/version") do
      Validation.digest(data["semantic_digest"], "/semantic_digest")
    end
  end

  defp unique(data) do
    ids = Enum.map(data, & &1["id"])

    if length(Enum.uniq(ids)) == length(ids),
      do: :ok,
      else: Error.refusal(:duplicate_identity, "/id")
  end

  defp references(data, table) do
    Validation.each(data, &Validation.each(&1["requires"], fn ref -> require_ref(ref, table) end))
  end

  defp require_ref(%{"id" => id, "version" => version, "semantic_digest" => digest}, table) do
    case table[id] do
      %{"version" => ^version, "semantic_digest" => ^digest} ->
        :ok

      _ ->
        Error.refusal(:unknown_required_contract, "/requires")
    end
  end

  defp acyclic(table) do
    case visit_all(Enum.sort(Map.keys(table)), table, MapSet.new(), MapSet.new()) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp visit_all(ids, table, done, active) do
    Enum.reduce_while(ids, {:ok, done}, fn id, {:ok, done} ->
      case visit(id, table, done, active) do
        {:ok, done} -> {:cont, {:ok, done}}
        error -> {:halt, error}
      end
    end)
  end

  defp visit(id, table, done, active) do
    cond do
      MapSet.member?(active, id) ->
        Error.refusal(:cyclic_contract, "/requires")

      MapSet.member?(done, id) ->
        {:ok, done}

      true ->
        ids = Enum.map(table[id]["requires"], & &1["id"])

        with {:ok, done} <- visit_all(ids, table, done, MapSet.put(active, id)) do
          {:ok, MapSet.put(done, id)}
        end
    end
  end
end
