defmodule Wotex.Thread.Mapping do
  @moduledoc "Pure Form mapping for the explicitly documented Wotex protocol profile."
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
         {:ok, uri} <- uri(href || Form.href(form)),
         {:ok, mapping} <- target(uri, type, input) do
      {:ok, Map.put(mapping, :form, Form.to_map(form))}
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

  defp target(
         %URI{scheme: "thread+unix", host: controller, port: nil, query: nil, path: path},
         :read,
         _
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
