defmodule WotexLabWorkbench.RoomProfiles do
  @moduledoc "Closed, passive host configuration for explicitly selected room transports."

  alias Wotex.Lab.Error
  alias Wotex.ThingDescription

  @keys ~w(id title host port unit_id)a

  @doc "Admits at most four distinct endpoint profiles without I/O or process startup."
  @spec new(term()) :: {:ok, map()} | {:error, Error.t()}
  def new(profiles) when is_list(profiles) and length(profiles) <= 4 do
    Enum.reduce_while(profiles, {:ok, %{}}, fn raw, {:ok, admitted} ->
      with {:ok, profile} <- admit(raw),
           false <- Map.has_key?(admitted, profile.id),
           false <-
             Enum.any?(admitted, fn {_, other} ->
               {other.host, other.port} == {profile.host, profile.port}
             end) do
        {:cont, {:ok, Map.put(admitted, profile.id, profile)}}
      else
        _ -> {:halt, invalid()}
      end
    end)
  end

  def new(_), do: invalid()

  @doc "Returns display-only choices; a busy endpoint remains unavailable to another room."
  @spec choices(map(), map(), pid() | nil) :: [map()]
  def choices(profiles, leases, room) do
    external =
      profiles
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn profile ->
        %{
          id: profile.id,
          title: profile.title,
          available: available?(Map.get(leases, profile.id), room)
        }
      end)

    [%{id: "loopback", title: "Loopback room", available: true} | external]
  end

  @doc "Resolves only a configured profile id or the built-in loopback profile."
  @spec fetch(map(), term()) :: {:ok, :loopback | map()} | {:error, Error.t()}
  def fetch(_, "loopback"), do: {:ok, :loopback}

  def fetch(profiles, id) when is_binary(id) do
    case Map.fetch(profiles, id) do
      {:ok, profile} -> {:ok, profile}
      :error -> {:error, Error.new(:unknown_room_profile, :room, "Room profile is unavailable")}
    end
  end

  def fetch(_, _), do: invalid()

  @doc "Projects the backend-owned reference descriptions onto the admitted Modbus routes."
  @spec specs(:loopback | map(), [map()]) :: {:ok, [map()]} | {:error, term()}
  def specs(:loopback, specs), do: {:ok, specs}

  def specs(profile, specs) do
    result =
      Enum.reduce_while(specs, {:ok, []}, fn spec, {:ok, acc} ->
        case ThingDescription.from_map(document(profile, spec)) do
          {:ok, td} ->
            {:cont,
             {:ok,
              [
                Map.merge(spec, %{
                  td: td,
                  id: ThingDescription.id(td),
                  scheme: "modbus+tcp",
                  state: %{}
                })
                | acc
              ]}}

          error ->
            {:halt, error}
        end
      end)

    case result do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp available?(nil, _), do: true
  defp available?(%{room: room}, room), do: true
  defp available?(_, _), do: false

  defp admit(profile) when is_map(profile) and not is_struct(profile) and map_size(profile) == 5 do
    with true <- Enum.sort(Map.keys(profile)) == Enum.sort(@keys),
         %{id: id, title: title, host: host, port: port, unit_id: unit} <- profile,
         true <- is_binary(id) and byte_size(id) in 1..32 and String.valid?(id) and id != "loopback",
         true <- Regex.match?(~r/\A[a-z][a-z0-9-]*\z/, id),
         true <- is_binary(title) and byte_size(title) in 1..64 and String.valid?(title),
         true <- String.trim(title) != "" and not Regex.match?(~r/\p{Cc}/u, title),
         true <- ipv4?(host),
         true <- is_integer(port) and port in 1..65_535,
         true <- is_integer(unit) and unit in 1..247 do
      {:ok, profile}
    else
      _ -> invalid()
    end
  end

  defp admit(_), do: invalid()

  defp ipv4?({a, b, c, d}),
    do: Enum.all?([a, b, c, d], &(is_integer(&1) and &1 in 0..255))

  defp ipv4?(_), do: false

  defp document(profile, spec) do
    original = ThingDescription.to_map(spec.td)

    property =
      case spec.key do
        "thermostat" -> {"temperature", "InputRegister", 1}
        "meter" -> {"power", "InputRegister", 3}
        "actuator" -> {"target", "HoldingRegister", 1}
      end

    {name, entity, address} = property

    operations =
      if spec.key == "actuator", do: ["readproperty", "writeproperty"], else: ["readproperty"]

    schema =
      original["properties"][name]
      |> Map.drop(["observable", "forms"])
      |> Map.put("forms", [form(profile, entity, address, operations)])

    original
    |> Map.put("id", "urn:wotex:lab:modbus:#{profile.id}:#{spec.key}")
    |> Map.put("title", profile.title <> " · " <> String.capitalize(spec.key))
    |> Map.put("security", ["none"])
    |> Map.put("securityDefinitions", %{"none" => %{"scheme" => "nosec"}})
    |> Map.put("properties", %{name => schema})
    |> Map.put("events", %{})
    |> Map.put("actions", actions(profile, original, spec.key))
  end

  defp actions(profile, original, "actuator") do
    action =
      original["actions"]["setTarget"]
      |> Map.put("forms", [
        form(profile, "HoldingRegister", 1, ["invokeaction"])
        |> Map.put("modv:function", "writeMultipleHoldingRegisters")
      ])

    %{"setTarget" => action}
  end

  defp actions(_, _, _), do: %{}

  defp form(profile, entity, address, operations),
    do: %{
      "href" =>
        "modbus+tcp://#{:inet.ntoa(profile.host)}:#{profile.port}/#{profile.unit_id}/#{address}?quantity=2",
      "op" => operations,
      "modv:entity" => entity,
      "modv:type" => "xsd:float"
    }

  defp invalid, do: {:error, Error.new(:invalid_room_profiles, :room, "Room profiles are invalid")}
end
