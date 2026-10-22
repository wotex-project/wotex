defmodule WotexLabWorkbench.Canvas do
  @moduledoc """
  Bounded presentation of a session's Things and smart-room wiring.

  Only explicit Property read or observation receipts supply values. Simulator state is not
  presented as an observation. Edges describe the admitted experiment wiring;
  moving or selecting them never changes a Form, a query or Action authority.
  """

  alias WotexLabWorkbench.{ThingProperties, ThingReadings}

  @positions %{"thermostat" => {160, 235}, "meter" => {160, 490}, "actuator" => {800, 490}}
  @titles %{"thermostat" => "Thermostat", "meter" => "Energy meter", "actuator" => "Actuator"}
  @properties %{"thermostat" => "temperature", "meter" => "power", "actuator" => "target"}
  @units %{"thermostat" => "°C", "meter" => "W", "actuator" => "°C target"}

  @doc "Builds a finite graph from already admitted session state without performing a read."
  @spec props([map()], [map()], %{optional(String.t()) => map()}, String.t() | nil) :: map()
  def props(things, runs, readings, selection \\ nil) do
    things =
      things
      |> Enum.sort_by(& &1.id)
      |> Enum.take(31)

    nodes =
      things
      |> Enum.with_index()
      |> Enum.map(fn {thing, index} ->
        node(thing, index, ThingReadings.get(readings, thing.key, @properties[thing.key]))
      end)

    process? = Enum.any?(things, &(&1.key in Map.keys(@positions)))
    nodes = if process?, do: [process(runs) | nodes], else: nodes
    ids = Enum.map(nodes, & &1["id"])

    %{
      "label" => "Connected Things",
      "nodes" => nodes,
      "edges" => Enum.filter(edges(), &(&1["source"] in ids and &1["target"] in ids))
    }
    |> selected(selection, ids)
  end

  defp selected(props, selection, ids) do
    if selection in ids or (is_binary(selection) and String.starts_with?(selection, "pin-")),
      do: Map.put(props, "selection", selection),
      else: props
  end

  @doc "Returns the stable presentation identity for one admitted Thing or inert entry."
  @spec id(map()) :: String.t()
  def id(%{key: key}) when key in ~w(thermostat meter actuator), do: "thing-" <> key
  def id(%{id: id}), do: "entry-" <> Base.encode16(:crypto.hash(:sha256, id), case: :lower)

  @doc "Returns the same bounded room label for a Thing's node and inspector."
  @spec title(map()) :: String.t()
  def title(thing), do: bounded(Map.get(@titles, thing.key, thing.title), 128)

  defp node(thing, index, reading) do
    {x, y} = Map.get(@positions, thing.key, {1080 + div(index, 5) * 260, 180 + rem(index, 5) * 180})
    read? = reading && reading.thing == thing.key && reading.property == @properties[thing.key]

    %{
      "id" => id(thing),
      "kind" => if(thing.consumable, do: "thing", else: "entry"),
      "title" => title(thing),
      "identity" =>
        Map.get(
          %{
            "thermostat" => "thermostat-01",
            "meter" => "energy-meter-01",
            "actuator" => "actuator-01"
          },
          thing.key,
          bounded(thing.id, 256)
        ),
      "operations" => node_operations(thing, reading),
      "value" => if(read?, do: bounded(inspect(reading.value), 128), else: "—"),
      "unit" => Map.get(@units, thing.key, ""),
      "status" =>
        cond do
          not thing.consumable -> "Inert"
          read? -> ThingReadings.status(reading)
          true -> "Not read"
        end,
      "detail" =>
        if(read?,
          do: ThingReadings.time(reading),
          else: ""
        ),
      "x" => x,
      "y" => y
    }
  end

  defp node_operations(thing, reading) do
    ThingProperties.operations_for_node(thing)
    |> Enum.map(fn operation ->
      if (operation == "observe" and reading) &&
           Map.get(reading, :state) in [:waiting, :live, :stale], do: "pause", else: operation
    end)
  end

  defp process(runs) do
    run = Enum.find(runs, &(&1.experiment == "smart_room"))

    %{
      "id" => "process-smart-room",
      "kind" => "process",
      "title" => "Smart room",
      "identity" => "smart_room",
      "value" => "",
      "unit" => "",
      "status" => if(run, do: to_string(run.status), else: "Idle"),
      "detail" => if(run, do: run.id, else: ""),
      "x" => 520,
      "y" => 365
    }
  end

  defp edges do
    [
      edge(
        "temperature",
        "thing-thermostat",
        "process-smart-room",
        "temperature · °C",
        "input",
        "temperature"
      ),
      edge("power", "thing-meter", "process-smart-room", "power · W", "input", "power"),
      edge("proposal", "process-smart-room", "thing-actuator", "proposal", "proposal", "input")
    ]
  end

  defp edge(id, source, target, label, kind, handle),
    do: %{
      "id" => id,
      "source" => source,
      "target" => target,
      "label" => label,
      "kind" => kind,
      "target_handle" => handle
    }

  defp bounded(value, bytes) when is_binary(value) do
    if byte_size(value) <= bytes,
      do: value,
      else:
        value
        |> String.codepoints()
        |> Enum.reduce_while("", fn cp, acc ->
          if byte_size(acc <> cp) <= bytes - 3, do: {:cont, acc <> cp}, else: {:halt, acc}
        end)
        |> Kernel.<>("…")
  end

  defp bounded(_, _), do: "Thing"
end
