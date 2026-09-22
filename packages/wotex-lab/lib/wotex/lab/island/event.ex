defmodule Wotex.Lab.Island.Event do
  @moduledoc "Validates one browser event against its Wotex Lab island descriptor."

  alias Wotex.Lab.Island.{CanonicalJSON, Component}

  @schema "wotex-lab-island-event/v1"
  @max_bytes 32 * 1_024
  @required_fields ~w(schema component instance_id client_revision event payload)
  @optional_fields ~w(command_id)
  @identifier ~r/\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/

  @doc "Validates a decoded event without returning rejected payload values."
  @spec validate(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def validate(component, instance_id, event) when is_map(event) and not is_struct(event) do
    with {:ok, descriptor} <- fetch(component),
         true <- closed_envelope?(event),
         true <- event["schema"] == @schema,
         true <- event["component"] == component and event["instance_id"] == instance_id,
         true <- valid_identifier?(instance_id),
         true <- decimal?(event["client_revision"]),
         event_name when is_binary(event_name) <- event["event"],
         %{} = event_descriptor <- descriptor["events"][event_name],
         true <- valid_command?(event_descriptor, event["command_id"]),
         %{} = payload <- event["payload"],
         true <- valid_payload?(event_descriptor["payload"], payload),
         {:ok, bytes} <- CanonicalJSON.encode(event),
         true <- byte_size(bytes) <= @max_bytes do
      {:ok, %{"event" => event_name, "command_id" => event["command_id"], "payload" => payload}}
    else
      _ -> {:error, :invalid_island_event}
    end
  end

  def validate(_, _, _), do: {:error, :invalid_island_event}

  defp fetch(component) do
    case Component.fetch(component) do
      {:ok, descriptor} -> {:ok, descriptor}
      :error -> {:error, :invalid_island_event}
    end
  end

  defp valid_command?(%{"effectful" => true}, value),
    do: valid_identifier?(value) and byte_size(value) <= 512

  defp valid_command?(_, nil), do: true
  defp valid_command?(_, value), do: valid_identifier?(value) and byte_size(value) <= 512

  defp valid_payload?("empty", payload), do: map_size(payload) == 0
  defp valid_payload?(field, payload) when is_binary(field), do: Map.keys(payload) == [field]
  defp valid_payload?(_, _), do: false

  defp closed_envelope?(event) do
    keys = Map.keys(event)

    Enum.all?(@required_fields, &(&1 in keys)) and
      Enum.all?(keys, &(&1 in (@required_fields ++ @optional_fields)))
  end

  defp valid_identifier?(value), do: is_binary(value) and Regex.match?(@identifier, value)
  defp decimal?(value), do: is_binary(value) and Regex.match?(~r/\A(?:0|[1-9][0-9]*)\z/, value)
end
