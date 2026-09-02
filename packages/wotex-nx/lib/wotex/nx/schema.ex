defmodule Wotex.Nx.Schema do
  @moduledoc "Immutable ordered feature schema and allocation limits."

  alias Wotex.Nx.{Error, Feature}

  @opaque t :: %__MODULE__{
            features: [Feature.t()],
            max_rows: pos_integer(),
            max_features: pos_integer(),
            max_width: pos_integer(),
            batch_key: term()
          }

  @enforce_keys [:features, :max_rows, :max_features, :max_width, :batch_key]
  defstruct @enforce_keys

  @doc "Builds a bounded ordered feature schema."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    features = Keyword.get(opts, :features)
    max_rows = Keyword.get(opts, :max_rows, 1_024)
    max_features = Keyword.get(opts, :max_features, 256)
    max_width = Keyword.get(opts, :max_width, 65_536)

    with :ok <- positive_limit(max_rows, :max_rows),
         :ok <- positive_limit(max_features, :max_features),
         :ok <- positive_limit(max_width, :max_width),
         :ok <- validate_features(features, max_features, max_width) do
      {:ok,
       %__MODULE__{
         features: features,
         max_rows: max_rows,
         max_features: max_features,
         max_width: max_width,
         batch_key: Keyword.get(opts, :batch_key, :default)
       }}
    end
  end

  def new(_opts),
    do:
      {:error,
       Error.new(:invalid_schema_options, :construction, "schema options must be a keyword list")}

  @doc "Returns features in the authoritative numerical order."
  @spec features(t()) :: [Feature.t()]
  def features(%__MODULE__{features: features}), do: features

  defp positive_limit(value, _name) when is_integer(value) and value > 0, do: :ok

  defp positive_limit(_value, name),
    do:
      {:error,
       Error.new(:invalid_limit, :construction, "schema limit must be positive", %{limit: name})}

  defp validate_features(features, max_features, max_width)
       when is_list(features) and features != [] do
    cond do
      not Enum.all?(features, &match?(%Feature{}, &1)) ->
        {:error,
         Error.new(:invalid_features, :construction, "schema features must contain Feature values")}

      length(features) > max_features ->
        {:error,
         Error.new(:feature_limit_exceeded, :limit, "schema exceeds max_features", %{
           count: length(features),
           max_features: max_features
         })}

      duplicate_names?(features) ->
        {:error, Error.new(:duplicate_feature_name, :construction, "feature names must be unique")}

      Enum.reduce(features, 0, &(Feature.width(&1) + &2)) > max_width ->
        {:error,
         Error.new(:width_limit_exceeded, :limit, "schema exceeds max_width", %{
           max_width: max_width
         })}

      true ->
        :ok
    end
  end

  defp validate_features(_features, _max_features, _max_width),
    do:
      {:error, Error.new(:invalid_features, :construction, "schema requires at least one Feature")}

  defp duplicate_names?(features) do
    names = Enum.map(features, & &1.name)
    length(names) != MapSet.size(MapSet.new(names))
  end
end
