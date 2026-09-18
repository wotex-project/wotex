defmodule WotexContinuum.Bench.Values do
  @moduledoc false

  # Synthetic wire-schema 2.0.0 inputs for the Wotex Continuum benchmarks.
  # Identifiers use reserved example URNs and `example` names only.

  alias WotexContinuum.Capability

  @spec schema_version() :: String.t()
  def schema_version, do: WotexContinuum.schema_version()

  # An observation proposal whose Property value is a scalar or a sampled
  # series of `count` readings.
  @spec observation_proposal(pos_integer() | nil) :: map()
  def observation_proposal(count) do
    %{
      "kind" => "observation_proposal",
      "schema_version" => schema_version(),
      "proposal_id" => "urn:example:proposal:1",
      "thing_id" => "urn:example:thing:pump-7",
      "affordance_type" => "property",
      "affordance_name" => "level",
      "value" => sample(count),
      "observed_at" => "2026-09-02T10:00:01Z",
      "sequence" => 8,
      "quality" => %{"status" => "measured"},
      "evidence" => [],
      "context" => %{
        "kind" => "execution_scope",
        "schema_version" => schema_version(),
        "execution_id" => "urn:example:execution:1",
        "node_id" => "edge-example-a",
        "mode" => %{
          "kind" => "mode",
          "schema_version" => schema_version(),
          "deployment" => "hybrid",
          "connectivity" => "intermittent",
          "extensions" => %{}
        },
        "observed_at" => "2026-09-02T10:00:01Z",
        "extensions" => %{}
      },
      "extensions" => %{}
    }
  end

  # A manifest that declares and requires `count` capabilities.
  @spec manifest(pos_integer()) :: map()
  def manifest(count) do
    %{
      "kind" => "continuum_manifest",
      "schema_version" => schema_version(),
      "manifest_id" => "urn:example:manifest:1",
      "artifact" => %{
        "name" => "example-edge-worker",
        "version" => "1.2.3",
        "digest" => "sha256:" <> String.duplicate("1", 64)
      },
      "compatibility" => %{
        "kind" => "compatibility",
        "schema_version" => schema_version(),
        "schema_requirement" => "~> 2.0",
        "required_capabilities" =>
          Enum.map(1..count, &%{"id" => capability_id(&1), "version_requirement" => "~> 2.0"}),
        "extensions" => %{}
      },
      "supported_modes" => ["hybrid", "connected_onprem", "air_gapped"],
      "capabilities" => Enum.map(1..count, &capability_map(&1, "2.1.0")),
      "extensions" => %{}
    }
  end

  # The capabilities a consumer host declares, each at `version`.
  @spec capabilities(pos_integer(), String.t()) :: [Capability.t()]
  def capabilities(count, version) do
    Enum.map(1..count, fn index ->
      {:ok, capability} = Capability.from_map(capability_map(index, version))
      capability
    end)
  end

  defp capability_map(index, version) do
    %{
      "kind" => "capability",
      "schema_version" => schema_version(),
      "id" => capability_id(index),
      "version" => version,
      "operations" => ["enqueue", "drain"],
      "modes" => ["hybrid", "connected_onprem"],
      "network" => "local",
      "degradation" => "queue",
      "extensions" => %{}
    }
  end

  defp capability_id(index), do: "example-capability-#{index}"

  defp sample(nil), do: 42.5
  defp sample(count), do: Enum.map(1..count, &(40.0 + rem(&1 * 7, 50) / 10))
end
