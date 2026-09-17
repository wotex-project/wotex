defmodule Wotex.Lab.Scenario do
  @moduledoc """
  A bounded, serializable experiment descriptor, with no executable authority.

  IDs and capabilities are strings. Deserialization must never create atoms or
  select modules. An approved host maps capabilities to explicitly supplied code.

  A descriptor records an identifier, a title, distinct capability IDs, a
  deterministic seed, and a maximum step count. Construction enforces the
  closed field set and the bounds defined by the Lab scenario contract.
  `to_map/1` returns the versioned, string-keyed representation used by
  frontends and evidence records.

  The value expresses admitted intent only. It contains no callback, process,
  credential, timeout implementation, or executable step. An execution host
  must reconstruct and validate boundary input, match requested capabilities
  to its reviewed configuration, and supply the revision-pinned scenario
  definition and resource budgets separately.

  `admitted/0` and `fetch_admitted/1` are the single source of the admitted
  descriptors. The `mix wotex.lab.scenarios` task, the MCP
  `wotex-lab://scenarios` resource, the optional Workbench control API and the
  cookbooks all read them, so every frontend presents identical descriptors.
  """

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Graph.Descriptors

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

  @doc """
  Returns the admitted descriptors, one per cookbook row, in catalogue order.

  Each admitted descriptor uses seed 1 and a step budget equal to its required
  step count. A host that needs another seed constructs a new descriptor.
  """
  @spec admitted() :: [t()]
  def admitted, do: Enum.map(Descriptors.scenarios(), &admitted_descriptor/1)

  @doc "Returns one admitted descriptor by its exact identifier."
  @spec fetch_admitted(term()) :: {:ok, t()} | {:error, Error.t()}
  def fetch_admitted(id) when is_binary(id) and byte_size(id) <= 128 do
    case Enum.find(Descriptors.scenarios(), &(&1.id == id)) do
      nil -> {:error, Error.new(:unknown_scenario, :construction, "scenario is not admitted")}
      descriptor -> {:ok, admitted_descriptor(descriptor)}
    end
  end

  def fetch_admitted(_),
    do: {:error, Error.new(:invalid_scenario_id, :construction, "scenario id is malformed")}

  @doc false
  @spec revalidate(term()) :: {:ok, t()} | {:error, Error.t()}
  def revalidate(%__MODULE__{} = scenario) do
    case new(
           id: scenario.id,
           title: scenario.title,
           capabilities: scenario.capabilities,
           seed: scenario.seed,
           max_steps: scenario.max_steps
         ) do
      {:ok, rebuilt} when rebuilt == scenario -> {:ok, rebuilt}
      {:ok, _} -> {:error, Error.new(:invalid_scenario, :preflight, "scenario is forged")}
      {:error, error} -> {:error, %{error | phase: :preflight}}
    end
  end

  def revalidate(_),
    do: {:error, Error.new(:invalid_scenario, :preflight, "scenario is invalid")}

  defp admitted_descriptor(descriptor) do
    {:ok, scenario} =
      new(
        id: descriptor.id,
        title: descriptor.title,
        capabilities: descriptor.capabilities,
        seed: 1,
        max_steps: max(length(descriptor.steps), 1)
      )

    scenario
  end

  defp valid_fields?(%{id: id, title: title, capabilities: caps, seed: seed, max_steps: steps}) do
    Options.identifier?(id) and is_binary(title) and byte_size(title) in 1..256 and
      String.valid?(title) and valid_capabilities?(caps) and
      is_integer(seed) and seed in 0..4_294_967_295 and
      is_integer(steps) and steps in 1..100_000
  end

  defp valid_fields?(_), do: false

  defp valid_capabilities?(caps) when is_list(caps) and length(caps) in 1..64,
    do: Enum.all?(caps, &Options.identifier?/1) and Enum.uniq(caps) == caps

  defp valid_capabilities?(_), do: false
end
