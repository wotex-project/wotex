defmodule WotexLabWorkbench.Experiments do
  @moduledoc """
  The admitted experiment catalogue and its parameter admission.

  Three Nx cookbook runs are offered: the checked-in thermal example, the
  window-anomaly lane over the deterministic simulator, and the smart room
  composed from disposable loopback Things. Parameters are typed, bounded and
  admitted from strings without creating atoms; a select value maps through a
  fixed table. Provenance names the fixture, dataset and model every run
  reads so the Experiments view can show it before any number.
  """

  alias Wotex.Lab.Error

  @type parameter :: %{
          name: String.t(),
          key: atom(),
          label: String.t(),
          type: :integer | :float | :select,
          default: term(),
          min: number() | nil,
          max: number() | nil,
          options: [{String.t(), term()}] | nil,
          help: String.t()
        }

  @type experiment :: %{
          id: String.t(),
          title: String.t(),
          summary: String.t(),
          kind: :immutable_dataset | :simulated_room,
          parameters: [parameter()],
          provenance: %{String.t() => String.t()},
          public_calls: [String.t()]
        }

  @backends [{"binary", Nx.BinaryBackend}]

  @experiments [
    %{
      id: "thermal",
      title: "Thermal observation to inert proposal",
      summary:
        "Two Kelvin observations become Celsius tensors; a mask-weighted mean plus one degree " <>
          "decodes into a setTarget proposal that nothing dispatches.",
      kind: :immutable_dataset,
      parameters: [
        %{
          name: "backend",
          key: :backend,
          label: "Nx backend",
          type: :select,
          default: "binary",
          min: nil,
          max: nil,
          options: @backends,
          help: "Selected for the run process only."
        }
      ],
      provenance: %{
        "fixture" => "fixtures/thermal/thing-description.json",
        "dataset" => "two checked-in observations (293.15 K, 295.15 K)",
        "model" => "Wotex.Lab.Examples.Thermal.target/1 (defn, no trained weights)"
      },
      public_calls: [
        "Wotex.ThingDescription.parse/1",
        "Wotex.DataSchema.new/1",
        "Wotex.Nx.Feature.new/1",
        "Wotex.Nx.Schema.new/1",
        "Wotex.Nx.Encoder.encode/3",
        "Nx.Defn.jit_apply/3",
        "Wotex.Nx.Decoder.decode/3"
      ]
    },
    %{
      id: "window_anomaly",
      title: "Windowed anomaly over a simulated thermal stream",
      summary:
        "Simulator samples are resampled into a window, encoded with an explicit fill policy and " <>
          "scored against the mask-weighted mean; the score, a persistence prediction and the " <>
          "last observation are decoded as inert outputs.",
      kind: :immutable_dataset,
      parameters: [
        %{
          name: "seed",
          key: :seed,
          label: "Simulator seed",
          type: :integer,
          default: 1,
          min: 1,
          max: 1_000_000,
          options: nil,
          help: "Deterministic stream identity."
        },
        %{
          name: "count",
          key: :count,
          label: "Samples",
          type: :integer,
          default: 32,
          min: 8,
          max: 512,
          options: nil,
          help: "Simulated samples, one per step."
        },
        %{
          name: "window_count",
          key: :window_count,
          label: "Window rows",
          type: :integer,
          default: 8,
          min: 2,
          max: 64,
          options: nil,
          help: "Rows in the resampled window."
        },
        %{
          name: "threshold",
          key: :threshold,
          label: "Anomaly threshold",
          type: :float,
          default: 1.5,
          min: 0.0,
          max: 100.0,
          options: nil,
          help: "Score at or above this is an anomaly."
        },
        %{
          name: "fill",
          key: :fill,
          label: "Fill value",
          type: :float,
          default: 18.0,
          min: -50.0,
          max: 100.0,
          options: nil,
          help: "Value written where a row has no accepted observation (mask 0)."
        },
        %{
          name: "backend",
          key: :backend,
          label: "Nx backend",
          type: :select,
          default: "binary",
          min: nil,
          max: nil,
          options: @backends,
          help: "Selected for the run process only."
        }
      ],
      provenance: %{
        "dataset" => "Wotex.Lab.Simulators.Thermal (seeded, versioned)",
        "model" => "Wotex.Lab.Examples.WindowAnomaly.score/1 (defn baseline, not trained)",
        "thing" => "urn:wotex:lab:room:simulated (synthetic source)"
      },
      public_calls: [
        "Wotex.Lab.Simulators.Thermal.generate/1",
        "Wotex.Nx.Window.new/1",
        "Wotex.Nx.Window.resample/3",
        "Wotex.Nx.Encoder.encode/2",
        "Nx.Defn.jit_apply/3",
        "Wotex.Nx.Decoder.decode/3"
      ]
    },
    %{
      id: "smart_room",
      title: "Smart room: discover, observe, infer, decide",
      summary:
        "Disposable loopback Things are discovered from the session Directory; the thermostat " <>
          "and meter readings become one Nx row and a setTarget proposal that the policy " <>
          "grants. Dispatch needs a separate explicit approval.",
      kind: :simulated_room,
      parameters: [
        %{
          name: "power_budget",
          key: :power_budget,
          label: "Power budget (W)",
          type: :float,
          default: 2_000.0,
          min: 100.0,
          max: 10_000.0,
          options: nil,
          help: "Observed power above this lowers the target."
        },
        %{
          name: "meter",
          key: :meter,
          label: "Energy meter",
          type: :select,
          default: "on",
          min: nil,
          max: nil,
          options: [{"on", true}, {"off", false}],
          help: "Off leaves the power feature filled with mask 0."
        },
        %{
          name: "principal",
          key: :principal,
          label: "Principal",
          type: :select,
          default: "operator",
          min: nil,
          max: nil,
          options: [{"operator", :operator}, {"guest", :guest}],
          help: "Only the operator is allowed by the room policy."
        },
        %{
          name: "ttl_ms",
          key: :ttl_ms,
          label: "Decision expiry (ms)",
          type: :integer,
          default: 120_000,
          min: 10,
          max: 600_000,
          options: nil,
          help: "A granted decision expires after this many milliseconds."
        }
      ],
      provenance: %{
        "fixture" => "fixtures/loopback/thing-description.json",
        "things" => "loopback thermostat, meter and actuator owned by this session",
        "model" => "Wotex.Lab.SmartRoom.Scenario.target/2 (defn rule, not trained)"
      },
      public_calls: [
        "Wotex.Lab.SmartRoom.Scenario.discover/3",
        "Wotex.Runtime.ConsumedThing.read_property/3",
        "Wotex.Lab.Continuum.Wire.proposal_from_observation/4",
        "Wotex.Lab.Continuum.Channel.send_value/4",
        "Wotex.Nx.Encoder.encode/2",
        "Nx.Defn.jit_apply/3",
        "Wotex.Nx.Decoder.decode/3",
        "Wotex.Lab.SmartRoom.Policy.decide/3"
      ]
    }
  ]

  @doc "Every admitted experiment in display order."
  @spec all() :: [experiment()]
  def all, do: @experiments

  @doc "Fetches one experiment by id."
  @spec fetch(term()) :: {:ok, experiment()} | {:error, Error.t()}
  def fetch(id) when is_binary(id) do
    case Enum.find(@experiments, &(&1.id == id)) do
      nil -> {:error, Error.new(:unknown_experiment, :admission, "experiment is not admitted")}
      experiment -> {:ok, experiment}
    end
  end

  def fetch(_),
    do: {:error, Error.new(:unknown_experiment, :admission, "experiment is not admitted")}

  @doc "Admits string parameters against the experiment's typed bounds."
  @spec admit(experiment(), map()) :: {:ok, keyword()} | {:error, Error.t()}
  def admit(experiment, params) when is_map(params) do
    admitted =
      Enum.reduce_while(experiment.parameters, {:ok, []}, fn parameter, {:ok, acc} ->
        raw = Map.get(params, parameter.name)

        case admit_value(parameter, raw) do
          {:ok, value} -> {:cont, {:ok, [{parameter.key, value} | acc]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    with {:ok, reversed} <- admitted, do: {:ok, Enum.reverse(reversed)}
  end

  def admit(_, _),
    do: {:error, Error.new(:invalid_parameters, :admission, "parameters must be a map")}

  @doc "The default parameter strings for a form."
  @spec defaults(experiment()) :: %{String.t() => String.t()}
  def defaults(experiment),
    do: Map.new(experiment.parameters, &{&1.name, to_string(&1.default)})

  defp admit_value(%{type: :select, options: options} = parameter, raw) do
    raw = raw || to_string(parameter.default)

    case List.keyfind(options, raw, 0) do
      {_, value} -> {:ok, value}
      nil -> reject(parameter)
    end
  end

  defp admit_value(%{type: :integer} = parameter, raw) do
    case parse(raw, parameter.default, &Integer.parse/1) do
      {:ok, value} when value >= parameter.min and value <= parameter.max -> {:ok, value}
      _ -> reject(parameter)
    end
  end

  defp admit_value(%{type: :float} = parameter, raw) do
    case parse(raw, parameter.default, &Float.parse/1) do
      {:ok, value} when value >= parameter.min and value <= parameter.max -> {:ok, value * 1.0}
      _ -> reject(parameter)
    end
  end

  defp parse(nil, default, _), do: {:ok, default}
  defp parse("", default, _), do: {:ok, default}

  defp parse(raw, _, parser) when is_binary(raw) and byte_size(raw) <= 32 do
    case parser.(String.trim(raw)) do
      {value, ""} -> {:ok, value}
      _ -> :error
    end
  end

  defp parse(_, _, _), do: :error

  defp reject(parameter) do
    {:error,
     Error.new(:invalid_parameter, :admission, "parameter is outside its admitted bounds",
       path: "/" <> parameter.name
     )}
  end
end
