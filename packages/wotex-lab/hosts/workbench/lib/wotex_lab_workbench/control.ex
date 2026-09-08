defmodule WotexLabWorkbench.Control do
  @moduledoc """
  Shared, read-only control-plane operations for HTTP and generated clients.

  Scenario and metric catalogue reads are inert. Evidence lookup requires the
  caller's already-admitted room and can return only a record retained by that
  room. This module does not open sessions, start rooms or dispatch effects.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Record
  alias Wotex.Lab.Graph.Descriptors
  alias Wotex.Lab.Metrics.Catalogue
  alias Wotex.Lab.Scenario
  alias WotexLabWorkbench.Room

  @doc "Returns every admitted Lab scenario as the versioned public descriptor."
  @spec scenarios() :: [map()]
  def scenarios do
    Enum.map(Descriptors.scenarios(), &scenario_map/1)
  end

  @doc "Returns one admitted scenario descriptor by exact identifier."
  @spec fetch_scenario(term()) :: {:ok, map()} | {:error, Error.t()}
  def fetch_scenario(id) when is_binary(id) and byte_size(id) <= 128 do
    case Enum.find(Descriptors.scenarios(), &(&1.id == id)) do
      nil -> {:error, error(:unknown_scenario, "scenario is not admitted")}
      descriptor -> {:ok, scenario_map(descriptor)}
    end
  end

  def fetch_scenario(_id), do: {:error, error(:invalid_scenario_id, "scenario id is malformed")}

  @doc "Returns one evidence record retained by the supplied room and exact digest."
  @spec fetch_evidence(pid(), term()) :: {:ok, map()} | {:error, Error.t()}
  def fetch_evidence(room, "sha256:" <> hex = digest)
      when is_pid(room) and byte_size(hex) == 64 do
    if hex =~ ~r/\A[0-9a-f]{64}\z/ do
      room
      |> Room.runs()
      |> Enum.find(&(&1.record_digest == digest))
      |> case do
        %{record: %Record{} = record} -> {:ok, Record.to_map(record)}
        _missing -> {:error, error(:unknown_evidence, "evidence record is not retained")}
      end
    else
      {:error, error(:invalid_record_id, "record digest is malformed")}
    end
  end

  def fetch_evidence(_room, _digest),
    do: {:error, error(:invalid_record_id, "record digest is malformed")}

  @doc "Returns the complete versioned metric catalogue as JSON-compatible data."
  @spec metrics_catalogue() :: map()
  def metrics_catalogue do
    %{
      "schema_version" => Catalogue.version(),
      "metrics" => Enum.map(Catalogue.metrics(), &metric_map/1)
    }
  end

  defp scenario_map(descriptor) do
    {:ok, scenario} =
      Scenario.new(
        id: descriptor.id,
        title: descriptor.title,
        capabilities: descriptor.capabilities,
        seed: 1,
        max_steps: max(length(descriptor.steps), 1)
      )

    Scenario.to_map(scenario)
  end

  defp metric_map(metric) do
    %{
      "id" => Atom.to_string(metric.id),
      "name" => metric.name,
      "version" => metric.version,
      "kind" => Atom.to_string(metric.type),
      "unit" => Atom.to_string(metric.unit),
      "dimensions" => Enum.map(metric.dimensions, &Atom.to_string/1),
      "scope" => Atom.to_string(metric.scope),
      "buckets" => metric.buckets,
      "description" => metric.description
    }
  end

  defp error(code, message), do: Error.new(code, :control_api, message)
end
