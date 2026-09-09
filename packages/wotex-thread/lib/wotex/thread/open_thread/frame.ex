defmodule Wotex.Thread.OpenThread.Frame do
  @moduledoc false

  alias Wotex.Thread.{Error, State}
  alias Wotex.Thread.OpenThread.DatasetWire

  @revision "5c8c318627954c99cd1a957a290bbd4b1027d04b"
  @roles ~w(disabled detached child router leader)
  @role_values %{
    "disabled" => :disabled,
    "detached" => :detached,
    "child" => :child,
    "router" => :router,
    "leader" => :leader
  }
  @errors %{
    "invalid_request" => :invalid_message,
    "invalid_dataset" => :invalid_dataset,
    "dataset_not_found" => :dataset_not_found,
    "invalid_state" => :invalid_state,
    "dataset_required" => :dataset_required,
    "creation_not_allowed" => :creation_not_allowed,
    "dataset_exists" => :dataset_exists,
    "formation_timeout" => :formation_timeout,
    "busy" => :busy,
    "storage_unavailable" => :storage_unavailable,
    "interface_in_use" => :interface_in_use,
    "already_open" => :already_open,
    "sdk_start_failed" => :transport_unavailable,
    "not_open" => :connection_closed,
    "not_supported" => :not_supported,
    "invalid_sdk_state" => :invalid_response,
    "io_failed" => :connection_closed,
    "remote_error" => :remote_error
  }

  @doc false
  @spec decode(term()) :: {:ok, map()} | :error
  def decode(line) when is_binary(line) and byte_size(line) < 131_072 do
    with :ok <- depth(line, 0, :outside),
         {:ok, value} <- Jason.decode(line, objects: :ordered_objects),
         {result, _} when is_map(result) <- normalize(value, 4096) do
      {:ok, result}
    else
      _ -> :error
    end
  catch
    :throw, :invalid_frame -> :error
  end

  def decode(_), do: :error

  @doc false
  @spec ready?(term()) :: boolean()
  def ready?(
        %{
          "version" => 1,
          "event" => "ready",
          "backend" => "openthread",
          "revision" => @revision
        } = frame
      ),
      do: map_size(frame) == 4

  def ready?(_), do: false

  @doc false
  @spec response(term(), String.t(), String.t()) :: {:ok, term()} | {:error, Error.t()} | :invalid
  def response(
        %{"version" => 1, "id" => id, "ok" => true, "result" => result} = frame,
        id,
        operation
      )
      when map_size(frame) == 4,
      do: value(result, operation)

  def response(
        %{"version" => 1, "id" => id, "ok" => false, "error" => error} = frame,
        id,
        operation
      )
      when map_size(frame) == 4,
      do: failure(error, operation)

  def response(_, _, _), do: :invalid

  defp depth(<<>>, 0, :outside), do: :ok
  defp depth(<<>>, _, _), do: :error
  defp depth(<<_, rest::binary>>, level, :escaped), do: depth(rest, level, :string)
  defp depth(<<?\\, rest::binary>>, level, :string), do: depth(rest, level, :escaped)
  defp depth(<<?", rest::binary>>, level, :string), do: depth(rest, level, :outside)
  defp depth(<<_, rest::binary>>, level, :string), do: depth(rest, level, :string)
  defp depth(<<?", rest::binary>>, level, :outside), do: depth(rest, level, :string)

  defp depth(<<byte, rest::binary>>, level, :outside) when byte in [?{, ?[] and level < 8,
    do: depth(rest, level + 1, :outside)

  defp depth(<<byte, rest::binary>>, level, :outside) when byte in [?}, ?]] and level > 0,
    do: depth(rest, level - 1, :outside)

  defp depth(<<byte, _::binary>>, _, :outside) when byte in [?{, ?[, ?}, ?]], do: :error
  defp depth(<<_, rest::binary>>, level, :outside), do: depth(rest, level, :outside)

  defp normalize(_, budget) when budget < 1, do: throw(:invalid_frame)

  defp normalize(%Jason.OrderedObject{values: pairs}, budget) do
    if length(pairs) > 1024, do: throw(:invalid_frame)

    Enum.reduce(pairs, {%{}, budget - 1}, fn {key, value}, {map, remaining} ->
      if Map.has_key?(map, key), do: throw(:invalid_frame)
      {value, remaining} = normalize(value, remaining)
      {Map.put(map, key, value), remaining}
    end)
  end

  defp normalize(values, budget) when is_list(values) do
    if length(values) > 1024, do: throw(:invalid_frame)
    Enum.map_reduce(values, budget - 1, &normalize/2)
  end

  defp normalize(value, budget), do: {value, budget - 1}

  defp value(value, operation) when operation in ["open", "inspect", "set_enabled"] do
    with %{
           "role" => role,
           "network_name" => name,
           "rloc16" => locator,
           "ipv6_enabled" => ipv6,
           "thread_enabled" => thread,
           "generation" => generation
         } <- value,
         true <- map_size(value) == 6 and role in @roles and generation == 1,
         {:ok, state} <-
           State.new(%{
             role: Map.fetch!(@role_values, role),
             network_name: name,
             rloc16: locator,
             ipv6_enabled: ipv6,
             thread_enabled: thread,
             generation: generation
           }) do
      {:ok, state}
    else
      _ -> :invalid
    end
  end

  defp value(value, "form_network") do
    case value(value, "inspect") do
      {:ok, %State{role: :leader, ipv6_enabled: true, thread_enabled: true}} = result -> result
      _ -> :invalid
    end
  end

  defp value(nil, "validate_dataset"), do: {:ok, nil}

  defp value(value, "get_dataset") do
    case DatasetWire.decode(value) do
      {:ok, dataset} -> {:ok, dataset}
      {:error, _} -> :invalid
    end
  end

  defp value(nil, "close"), do: {:ok, nil}
  defp value(role, "state") when role in @roles, do: {:ok, role}
  defp value(nil, operation) when operation in ["network_name", "rloc16"], do: {:ok, nil}

  defp value(locator, "rloc16") when is_integer(locator) and locator in 0..65_535,
    do: {:ok, locator}

  defp value(text, operation) when is_binary(text) and operation in ["version", "network_name"] do
    maximum = if operation == "version", do: 1024, else: 16

    if byte_size(text) in 1..maximum and String.valid?(text) and
         not Regex.match?(~r/[\x00-\x1f\x7f]/, text),
       do: {:ok, text},
       else: :invalid
  end

  defp value(_, _), do: :invalid

  defp failure(%{"state" => state} = error, "form_network") do
    with {:ok, state} <- value(state, "inspect"),
         {:error, error} <- failure(Map.delete(error, "state")) do
      {:error, %{error | details: Map.put(error.details, :state, state)}}
    else
      _ -> :invalid
    end
  end

  defp failure(error, _), do: failure(error)

  defp failure(%{"code" => code} = error) when map_size(error) == 1 do
    case Map.fetch(@errors, code) do
      {:ok, code} -> {:error, Error.new(code)}
      :error -> :invalid
    end
  end

  defp failure(%{"code" => "remote_error", "status" => status} = error)
       when map_size(error) == 2 and is_integer(status) and status in 0..65_535,
       do: {:error, Error.new(:remote_error, nil, %{status: status})}

  defp failure(_), do: :invalid
end
