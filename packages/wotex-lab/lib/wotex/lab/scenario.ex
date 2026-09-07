defmodule Wotex.Lab.Scenario do
  @moduledoc """
  A bounded, serializable experiment descriptor, with no executable authority.

  IDs and capabilities are strings. Deserialization must never create atoms or
  select modules. An approved host maps capabilities to explicitly supplied code.
  """

  alias Wotex.Lab.{Error, Options}

  @typedoc "Version-one descriptor; construct through `new/1`."
  @opaque t :: %__MODULE__{
            id: String.t(),
            title: String.t(),
            capabilities: [String.t()],
            seed: non_neg_integer(),
            max_steps: pos_integer()
          }
  @enforce_keys [:id, :title, :capabilities, :seed, :max_steps]
  defstruct @enforce_keys

  @doc "Accepts ID, title, unique capabilities, an explicit seed and a positive step budget."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) do
    with :ok <- Options.validate(opts, @enforce_keys) do
      fields = Map.new(opts)

      if valid_fields?(fields) do
        {:ok, struct!(__MODULE__, fields)}
      else
        {:error, Error.new(:invalid_scenario, :construction, "scenario fields are invalid")}
      end
    end
  end

  @doc "Returns a versioned string-keyed map from an accepted descriptor."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = scenario) do
    %{
      "schema_version" => "1.0.0",
      "id" => scenario.id,
      "title" => scenario.title,
      "capabilities" => scenario.capabilities,
      "seed" => scenario.seed,
      "max_steps" => scenario.max_steps
    }
  end

  defp valid_fields?(%{id: id, title: title, capabilities: caps, seed: seed, max_steps: steps}) do
    Options.identifier?(id) and is_binary(title) and byte_size(title) in 1..256 and
      String.valid?(title) and valid_capabilities?(caps) and
      is_integer(seed) and seed in 0..4_294_967_295 and
      is_integer(steps) and steps in 1..100_000
  end

  defp valid_fields?(_fields), do: false

  defp valid_capabilities?(caps) when is_list(caps) and length(caps) in 1..64,
    do: Enum.all?(caps, &Options.identifier?/1) and Enum.uniq(caps) == caps

  defp valid_capabilities?(_caps), do: false
end
