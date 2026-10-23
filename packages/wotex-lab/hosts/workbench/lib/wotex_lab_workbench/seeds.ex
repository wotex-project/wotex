defmodule WotexLabWorkbench.Seeds do
  @moduledoc """
  Reads the generated reference-room seed without starting a room or executing code.

  `mix seed` owns generation from `priv/seeds.exs`. The release consumes only
  bounded JSON. Missing or invalid data refuses room startup; it never supplies
  fallback Things, readings, Runs or metrics.
  """

  alias Wotex.Lab.Error
  alias Wotex.ThingDescription

  @maximum_bytes 65_536
  @roles %{"thermostat" => :thermostat, "meter" => :meter, "actuator" => :actuator}
  @schemes %{"thermostat" => "sim-thermostat", "meter" => "sim-meter", "actuator" => "loopback"}

  @doc "Loads the three declared reference Things from a generated seed file."
  @spec room(Path.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def room(path \\ Application.app_dir(:wotex_lab_workbench, "priv/seeds/room.json"))

  def room(path) when is_binary(path) do
    with {:ok, %{type: :regular, size: size}} when size <= @maximum_bytes <- File.lstat(path),
         {:ok, bytes} when byte_size(bytes) <= @maximum_bytes <- File.read(path),
         {:ok, value} <- JSON.decode(bytes) do
      admit_room(value)
    else
      _ -> invalid()
    end
  end

  def room(_), do: invalid()

  @doc "Admits the closed reference-room seed without allocating any processes."
  @spec admit_room(term()) :: {:ok, [map()]} | {:error, Error.t()}
  def admit_room(%{"schema" => "wotex-lab-room-seed/v1", "things" => things} = value)
      when map_size(value) == 2 and is_list(things) and length(things) == 3 do
    with true <- Enum.sort(Enum.map(things, &key/1)) == Enum.sort(Map.keys(@roles)),
         {:ok, admitted} <- admit_things(things),
         true <- MapSet.size(MapSet.new(admitted, & &1.id)) == 3 do
      {:ok, admitted}
    else
      _ -> invalid()
    end
  end

  def admit_room(_), do: invalid()

  defp admit_things(things) do
    result =
      Enum.reduce_while(things, {:ok, []}, fn thing, {:ok, acc} ->
        case admit_thing(thing) do
          {:ok, admitted} -> {:cont, {:ok, [admitted | acc]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, admitted} -> {:ok, Enum.reverse(admitted)}
      error -> error
    end
  end

  defp admit_thing(
         %{"key" => key, "scheme" => scheme, "state" => state, "document" => document} = value
       )
       when map_size(value) == 4 and is_map_key(@roles, key) do
    with true <- scheme == @schemes[key] and valid_state?(state),
         {:ok, td} <- ThingDescription.from_map(document),
         %{"id" => id} when is_binary(id) and byte_size(id) > 0 <- ThingDescription.to_map(td) do
      {:ok, %{key: key, role: @roles[key], scheme: scheme, state: state, td: td, id: id}}
    else
      _ -> invalid()
    end
  end

  defp admit_thing(_), do: invalid()

  defp valid_state?(state) when is_map(state) and map_size(state) in 1..8 do
    Enum.all?(state, fn {key, value} ->
      is_binary(key) and byte_size(key) in 1..128 and is_number(value) and
        value >= -1_000_000_000 and value <= 1_000_000_000
    end)
  end

  defp valid_state?(_), do: false
  defp key(%{"key" => key}) when is_binary(key), do: key
  defp key(_), do: ""

  defp invalid,
    do: {:error, Error.new(:invalid_seed, :room, "reference-room seed is unavailable or invalid")}
end
