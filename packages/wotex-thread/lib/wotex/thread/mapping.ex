defmodule Wotex.Thread.Mapping do
  @moduledoc """
  Maps a W3C Web of Things Form to a read-only Thread management request.

  `command/4` accepts a declared Property read and parses a `thread+unix` href.
  The supported paths map to daemon state, version, network-name, or 16-bit
  Routing Locator (RLOC16) commands, and the URI host becomes the explicit
  controller target. The source
  Form map is retained so unknown extension terms remain available to the
  consumer.

  Mapping is pure and does not open a Unix socket, contact an OpenThread daemon,
  or change an Operational Dataset. Malformed URIs, user information,
  fragments, unsupported paths, and operations other than `readproperty`
  return `Wotex.Thread.Error`. Success does not authorize daemon access or turn
  Thread management data into application Property truth.
  """
  alias Wotex.Form
  alias Wotex.Thread.Error
  @operations %{readproperty: :read}

  @doc "Maps a selected Form, preserving extensions and requiring an explicit target identity."
  @spec command(Form.t(), atom(), term(), String.t() | nil) :: {:ok, map()} | {:error, Error.t()}
  def command(form, operation, input, href \\ nil)

  def command(%Form{} = form, operation, input, href) do
    affordance = if operation == :invokeaction, do: :action, else: :property

    with {:ok, type} <- Map.fetch(@operations, operation),
         true <- Atom.to_string(operation) in Form.operations(form, for: affordance),
         fields = Form.to_map(form),
         :ok <- media(fields),
         {:ok, uri} <- uri(href || Form.href(form)),
         {:ok, mapping} <- target(uri, type, input) do
      {:ok, Map.put(mapping, :form, fields)}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:unsupported_operation)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_form_address)}
  end

  def command(_, _, _, _), do: {:error, Error.new(:invalid_form)}

  defp media(fields) do
    if Map.has_key?(fields, "contentType"),
      do: {:error, Error.new(:unsupported_content_type)},
      else: :ok
  end

  defp uri(href) when is_binary(href) and byte_size(href) <= 4096 do
    case URI.parse(href) do
      %URI{userinfo: nil, fragment: nil} = uri -> {:ok, uri}
      _ -> {:error, Error.new(:invalid_form_address)}
    end
  end

  defp uri(_), do: {:error, Error.new(:invalid_form_address)}

  defp target(
         %URI{scheme: "thread+unix", host: controller, port: nil, query: nil, path: path},
         :read,
         nil
       )
       when is_binary(controller) and byte_size(controller) > 0 do
    case %{
           "/state" => :state,
           "/version" => :version,
           "/network-name" => :network_name,
           "/rloc16" => :rloc16
         }[path] do
      nil -> {:error, Error.new(:invalid_form_address)}
      type -> {:ok, %{target: controller, message: %{type: type}}}
    end
  end

  defp target(_, _, _), do: {:error, Error.new(:invalid_form_address)}
end
