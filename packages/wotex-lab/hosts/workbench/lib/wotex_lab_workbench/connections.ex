defmodule WotexLabWorkbench.Connections do
  @moduledoc """
  Room-owned bindings for the reference smart-room process.

  Configuration selects only already admitted reference affordances. It performs
  no read, transport startup or Action dispatch. The room serializes mutations;
  a draft's revision cannot replace a newer binding.
  """

  alias Wotex.Form
  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Canvas, ThingProperties, ThingReadings}

  @ports ~w(temperature power proposal)
  @defaults %{
    "temperature" => %{"thing" => "thermostat", "affordance" => "temperature"},
    "power" => %{"thing" => "meter", "affordance" => "power"},
    "proposal" => %{"thing" => "actuator", "affordance" => "setTarget"}
  }
  @maximum_revision 1_000_000_000

  @type binding :: %{String.t() => String.t()} | nil
  @type t :: %{revision: non_neg_integer(), bindings: %{String.t() => binding()}}

  @doc "Returns the finite, ordered reference process ports."
  @spec ports() :: [String.t()]
  def ports, do: @ports

  @doc "Returns the compact label for one declared process port."
  @spec title(String.t()) :: String.t()
  def title("temperature"), do: "Temperature"
  def title("power"), do: "Power"
  def title("proposal"), do: "Action proposal"
  def title(_), do: "Connection"

  @doc "Builds the previous sample-room wiring only where its affordances are admitted."
  @spec new([map()]) :: t()
  def new(things) do
    bindings =
      Map.new(@ports, fn port ->
        expected = @defaults[port]
        found = Enum.find(options(things, port), &matches?(&1, expected))
        {port, if(found, do: expected)}
      end)

    %{revision: 0, bindings: bindings}
  end

  @doc "Lists eligible current affordances in deterministic Thing/Property order."
  @spec options([map()], String.t()) :: [map()]
  def options(things, port) when port in @ports do
    things
    |> Enum.filter(&(Map.get(&1, :consumable) == true))
    |> Enum.sort_by(& &1.id)
    |> Enum.take(31)
    |> Enum.flat_map(&thing_options(&1, port))
    |> Enum.sort_by(&{&1.thing_id, &1.affordance != port, &1.affordance})
  end

  def options(_, _), do: []

  @doc "Resolves an exact configured binding against current declarations without executing it."
  @spec fetch(t(), [map()], String.t()) :: {:ok, map()} | {:error, Error.t()}
  def fetch(model, things, port) when port in @ports do
    binding = model.bindings[port]

    case Enum.find(options(things, port), &matches?(&1, binding)) do
      nil -> error(:missing_connection, title(port) <> " connection is required")
      option -> {:ok, option}
    end
  end

  def fetch(_, _, _), do: invalid()

  @doc "Creates an editable draft from the current binding or the first eligible option."
  @spec draft(t(), [map()], String.t()) :: {:ok, map()} | {:error, Error.t()}
  def draft(model, things, port) when port in @ports do
    option =
      case fetch(model, things, port) do
        {:ok, selected} -> selected
        _ -> List.first(options(things, port))
      end

    {:ok,
     %{
       "port" => port,
       "thing" => if(option, do: option.thing, else: ""),
       "affordance" => if(option, do: option.affordance, else: ""),
       "revision" => Integer.to_string(model.revision)
     }}
  end

  def draft(_, _, _), do: invalid()

  @doc "Checks the closed bounded draft shape; it never supplies authority."
  @spec draft?(term()) :: boolean()
  def draft?(raw) do
    is_map(raw) and not is_struct(raw) and
      Enum.sort(Map.keys(raw)) == ~w(affordance port revision thing) and
      raw["port"] in @ports and
      Enum.all?(~w(thing affordance), &text?(raw[&1])) and revision?(raw["revision"])
  end

  @doc "Changes one exact binding only at its current revision."
  @spec change(t(), [map()], term()) :: {:ok, t()} | {:error, Error.t()}
  def change(model, things, raw) do
    with true <- draft?(raw),
         :ok <- current(model, raw["revision"]),
         %{} = option <-
           Enum.find(options(things, raw["port"]), &matches?(&1, raw)) do
      put(model, raw["port"], %{"thing" => option.thing, "affordance" => option.affordance})
    else
      {:error, error} -> {:error, error}
      nil -> error(:incompatible_connection, "Choose a compatible admitted affordance")
      _ -> invalid()
    end
  end

  @doc "Removes one process binding with the same revision protection as Apply."
  @spec remove(t(), term()) :: {:ok, t()} | {:error, Error.t()}
  def remove(model, raw) when is_map(raw) and not is_struct(raw) do
    with true <- Enum.sort(Map.keys(raw)) == ~w(port revision),
         true <- raw["port"] in @ports,
         :ok <- current(model, raw["revision"]) do
      put(model, raw["port"], nil)
    else
      {:error, error} -> {:error, error}
      _ -> invalid()
    end
  end

  def remove(_, _), do: invalid()

  @doc "Turns a bounded handle gesture into an uncommitted compatible draft."
  @spec gesture(t(), [map()], term()) :: {:ok, map()} | {:error, Error.t()}
  def gesture(model, things, raw) when is_map(raw) and not is_struct(raw) do
    with true <- Enum.sort(Map.keys(raw)) == ~w(source target target_handle),
         true <- Enum.all?(Map.values(raw), &text?/1),
         {:ok, port, node} <- direction(raw),
         %{} = thing <- Enum.find(things, &(Canvas.id(&1) == node)),
         options when options != [] <- Enum.filter(options(things, port), &(&1.thing == thing.key)),
         option <- Enum.find(options, &matches?(&1, model.bindings[port])) || hd(options) do
      {:ok,
       %{
         "port" => port,
         "thing" => option.thing,
         "affordance" => option.affordance,
         "revision" => Integer.to_string(model.revision)
       }}
    else
      _ -> error(:incompatible_connection, "These endpoints have no compatible connection")
    end
  end

  def gesture(_, _, _), do: invalid()

  @doc "Projects applied bindings and exact cached receipts into the closed canvas edge shape."
  @spec edges(t(), [map()], map()) :: [map()]
  def edges(model, things, readings) do
    Enum.flat_map(@ports, fn port ->
      case fetch(model, things, port) do
        {:ok, option} ->
          thing = Enum.find(things, &(&1.key == option.thing))
          proposal? = port == "proposal"

          [
            %{
              "id" => port,
              "source" => if(proposal?, do: "process-smart-room", else: Canvas.id(thing)),
              "target" => if(proposal?, do: Canvas.id(thing), else: "process-smart-room"),
              "label" => bounded(label(option, readings)),
              "kind" => if(proposal?, do: "proposal", else: "input"),
              "target_handle" => if(proposal?, do: "input", else: port)
            }
          ]

        _ ->
          []
      end
    end)
  end

  @doc "Returns exact endpoint references accepted by the immutable run evidence contract."
  @spec inputs(t(), [map()]) :: [String.t()]
  def inputs(model, things) do
    Enum.map(@ports, fn port ->
      fields =
        case fetch(model, things, port) do
          {:ok, option} ->
            [port, option.thing_id, Atom.to_string(option.kind), option.affordance, option.unit]

          _ ->
            [port, nil]
        end

      "connection:" <> Jason.encode!(fields)
    end)
  end

  @doc "Hashes ordered connection values without depending on map iteration."
  @spec digest(t()) :: String.t()
  def digest(model) do
    values =
      Enum.map(@ports, fn port ->
        binding = model.bindings[port]
        [port, binding && binding["thing"], binding && binding["affordance"]]
      end)

    :crypto.hash(:sha256, Jason.encode!([model.revision, values]))
    |> Base.encode16(case: :lower)
  end

  defp thing_options(thing, "proposal") do
    action = get_in(thing, [:document, "actions", "setTarget"])
    schema = action && action["input"]

    if thing.key == "actuator" and scalar?(schema, "Cel") and invokes?(action) do
      [option(thing, "setTarget", "Cel", :action, schema)]
    else
      []
    end
  end

  defp thing_options(thing, port) do
    unit = if port == "temperature", do: "Cel", else: "W"

    thing
    |> ThingProperties.rows()
    |> Enum.filter(& &1.readable)
    |> Enum.flat_map(fn row ->
      schema = get_in(thing, [:document, "properties", row.name])

      if scalar?(schema, unit),
        do: [option(thing, row.name, unit, :property, schema)],
        else: []
    end)
  end

  defp option(thing, name, unit, kind, schema),
    do: %{
      thing: thing.key,
      thing_id: thing.id,
      affordance: name,
      unit: unit,
      kind: kind,
      schema: schema
    }

  defp scalar?(schema, unit) when is_map(schema),
    do: schema["type"] in ~w(number integer) and schema["unit"] == unit

  defp scalar?(_, _), do: false

  defp invokes?(action) when is_map(action) do
    Enum.any?(Map.get(action, "forms", []), fn form ->
      case Form.new(form, for: :action) do
        {:ok, value} -> "invokeaction" in Form.operations(value, for: :action)
        _ -> false
      end
    end)
  end

  defp invokes?(_), do: false

  defp direction(%{
         "source" => source,
         "target" => "process-smart-room",
         "target_handle" => port
       })
       when port in ~w(temperature power),
       do: {:ok, port, source}

  defp direction(%{
         "source" => "process-smart-room",
         "target" => target,
         "target_handle" => "input"
       }),
       do: {:ok, "proposal", target}

  defp direction(_), do: invalid()

  defp matches?(option, %{"thing" => thing, "affordance" => name}),
    do: option.thing == thing and option.affordance == name

  defp matches?(_, _), do: false

  defp current(model, revision) do
    cond do
      not revision?(revision) -> invalid()
      Integer.to_string(model.revision) == revision -> :ok
      true -> error(:stale_connection, "Connections changed. Reload this draft")
    end
  end

  defp put(model, port, binding) do
    cond do
      model.bindings[port] == binding ->
        {:ok, model}

      model.revision >= @maximum_revision ->
        error(:connection_limit, "Connection revision limit reached")

      true ->
        {:ok,
         %{model | revision: model.revision + 1, bindings: Map.put(model.bindings, port, binding)}}
    end
  end

  defp label(%{kind: :action, affordance: name}, _), do: name <> " · proposal"

  defp label(option, readings) do
    unit = if option.unit == "Cel", do: "°C", else: option.unit

    case ThingReadings.get(readings, option.thing, option.affordance) do
      nil ->
        option.affordance <> " · " <> unit

      reading ->
        suffix =
          if ThingReadings.status(reading) == "Live",
            do: "",
            else: " · " <> ThingReadings.status(reading)

        option.affordance <> " · " <> inspect(reading.value) <> " " <> unit <> suffix
    end
  end

  defp bounded(value) do
    if byte_size(value) <= 128 do
      value
    else
      value
      |> String.codepoints()
      |> Enum.reduce_while("", fn cp, acc ->
        if byte_size(acc <> cp) <= 125, do: {:cont, acc <> cp}, else: {:halt, acc}
      end)
      |> Kernel.<>("…")
    end
  end

  defp text?(value), do: is_binary(value) and byte_size(value) <= 128 and String.valid?(value)

  defp revision?(value),
    do:
      is_binary(value) and byte_size(value) <= 10 and
        Regex.match?(~r/\A(?:0|[1-9][0-9]*)\z/, value) and
        String.to_integer(value) <= @maximum_revision

  defp invalid, do: error(:invalid_connection, "Connection parameters are malformed")
  defp error(code, message), do: {:error, Error.new(code, :connections, message)}
end
