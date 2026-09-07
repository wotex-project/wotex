defmodule WotexContinuum.Limits do
  @moduledoc """
  Explicit resource limits for continuum JSON admission.

  Limits are values, so a consumer chooses policy without ambient
  configuration. `WotexContinuum.Codec.decode/2` hands them to
  `Wotex.JSON.decode/2`, which checks byte size and UTF-8 validity first,
  bounds nesting depth and string size with a lexical scan before
  allocation-heavy decoding, copies decoded strings away from the source
  binary, and then rejects duplicate object members and oversized collections,
  node counts, and depth. Continuum semantic validation runs on the decoded map
  afterwards.

  | Option | Default | Bounds |
  | --- | --- | --- |
  | `:max_bytes` | 1,048,576 | JSON source bytes |
  | `:max_depth` | 32 | nested containers, decoded or native |
  | `:max_nodes` | 100,000 | JSON values including containers |
  | `:max_string_bytes` | 262,144 | one string value or object key |
  | `:max_collection_size` | 10,000 | members of one object or array |

  `max_depth/0` is the single nesting bound. It applies to decoded source and,
  measured from the validated value, to native JSON values supplied to a
  constructor.
  """

  alias WotexContinuum.{Error, Validation}

  @max_bytes 1_048_576
  @max_depth 32
  @max_nodes 100_000
  @max_string_bytes 262_144
  @max_collection_size 10_000

  @enforce_keys [:max_bytes, :max_depth, :max_nodes, :max_string_bytes, :max_collection_size]
  defstruct max_bytes: @max_bytes,
            max_depth: @max_depth,
            max_nodes: @max_nodes,
            max_string_bytes: @max_string_bytes,
            max_collection_size: @max_collection_size

  @type t :: %__MODULE__{
          max_bytes: pos_integer(),
          max_depth: pos_integer(),
          max_nodes: pos_integer(),
          max_string_bytes: pos_integer(),
          max_collection_size: pos_integer()
        }

  @doc "Returns conservative default admission limits."
  @spec defaults() :: %__MODULE__{
          max_bytes: 1_048_576,
          max_depth: 32,
          max_nodes: 100_000,
          max_string_bytes: 262_144,
          max_collection_size: 10_000
        }
  def defaults do
    %__MODULE__{
      max_bytes: @max_bytes,
      max_depth: @max_depth,
      max_nodes: @max_nodes,
      max_string_bytes: @max_string_bytes,
      max_collection_size: @max_collection_size
    }
  end

  @doc "Returns the single nesting bound applied to decoded and native JSON."
  @spec max_depth() :: 32
  def max_depth, do: @max_depth

  @doc "Builds validated limits from a keyword list or map."
  @spec new(keyword() | map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = limits), do: validate(limits)

  def new(options) when is_list(options) do
    with :ok <- Validation.options(options, allowed()) do
      options
      |> Map.new()
      |> new()
    end
  end

  def new(options) when is_map(options) do
    with {:ok, normalized} <- Validation.normalize(options, allowed()) do
      defaults()
      |> Map.from_struct()
      |> Map.merge(normalized)
      |> then(&struct!(__MODULE__, &1))
      |> validate()
    end
  end

  def new(_), do: Error.error(:invalid_type, :limits, nil, "expected limit options")

  @doc false
  @spec to_options(t()) :: keyword()
  def to_options(%__MODULE__{} = limits) do
    [
      max_bytes: limits.max_bytes,
      max_depth: limits.max_depth,
      max_nodes: limits.max_nodes,
      max_string_bytes: limits.max_string_bytes,
      max_collection_size: limits.max_collection_size
    ]
  end

  defp allowed, do: Map.keys(Map.from_struct(defaults()))

  defp validate(%__MODULE__{} = limits) do
    fields = Map.from_struct(limits)

    case Enum.find(fields, fn {_, value} -> not (is_integer(value) and value > 0) end) do
      nil ->
        {:ok, limits}

      {key, _} ->
        Error.error(:invalid_limit, :limits, nil, "limit must be a positive integer", %{
          option: key
        })
    end
  end
end
