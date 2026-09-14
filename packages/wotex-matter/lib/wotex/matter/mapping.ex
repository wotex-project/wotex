defmodule Wotex.Matter.Mapping do
  @moduledoc """
  Maps a W3C Web of Things Form to a concrete Matter interaction request.

  `command/4` accepts Property reads, writes and observations, Action
  invocations, and Event subscriptions declared by the Form. It parses a
  `matter` href into the fabric, node, endpoint, cluster, and member required by
  `Wotex.Matter.Address`, attaches write or invoke input, and returns an
  immutable request map. The original Form map is retained so unknown extension
  terms are preserved.

  ## Semantics

  Mapping is pure and performs no commissioning, fabric lookup, or SDK call. It
  rejects malformed hrefs, user information, fragments, wildcard paths, and
  unsupported operations as `Wotex.Matter.Error`. Successful mapping means only
  that the Form fits the documented package profile. It does not authorize the
  interaction, validate cluster semantics, or prove a device effect.
  """
  alias Wotex.Form
  alias Wotex.Matter.{Address, Error}

  @operations %{
    readproperty: {:read, :property, :attribute},
    writeproperty: {:write, :property, :attribute},
    observeproperty: {:subscribe, :property, :attribute},
    invokeaction: {:invoke, :action, :command},
    subscribeevent: {:subscribe, :event, :event}
  }

  @doc "Maps a selected Form, preserving extensions and requiring an explicit target identity."
  @spec command(Form.t(), atom(), term(), String.t() | nil) :: {:ok, map()} | {:error, Error.t()}
  def command(form, operation, input, href \\ nil)

  def command(%Form{} = form, operation, input, href) do
    with {:ok, {type, affordance, kind}} <- Map.fetch(@operations, operation),
         true <- Atom.to_string(operation) in Form.operations(form, for: affordance),
         {:ok, uri} <- uri(href || Form.href(form)),
         {:ok, mapping} <- target(uri, type, input) do
      {:ok,
       mapping
       |> Map.put(:kind, kind)
       |> Map.put(:form, Form.to_map(form))}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:unsupported_operation)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_form_address)}
  end

  def command(_, _, _, _), do: {:error, Error.new(:invalid_form)}

  defp uri(href) when is_binary(href) and byte_size(href) <= 4096 do
    case URI.parse(href) do
      %URI{userinfo: nil, fragment: nil} = uri -> {:ok, uri}
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp uri(_), do: {:error, Error.new(:invalid_form_address)}

  defp target(%URI{scheme: "matter", host: fabric, port: nil, query: nil, path: path}, type, input) do
    with [node, endpoint, cluster, member] <- String.split(path || "", "/", trim: true),
         {:ok, address} <-
           Address.new(%{
             fabric_id: number(fabric),
             node_id: number(node),
             endpoint: number(endpoint),
             cluster: number(cluster),
             member: number(member)
           }) do
      message =
        address
        |> Map.from_struct()
        |> Map.put(:type, type)
        |> input(type, input)

      {:ok, %{target: Integer.to_string(address.fabric_id), message: message}}
    else
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp target(_, _, _), do: {:error, Error.new(:invalid_form_address)}

  defp number(text) when is_binary(text) do
    case Integer.parse(text) do
      {n, ""} -> n
      _ -> :invalid
    end
  end

  defp number(_), do: :invalid

  defp input(message, type, value) when type in [:write, :invoke],
    do: Map.put(message, :value, value)

  defp input(message, _, _), do: message
end
