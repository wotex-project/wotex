defmodule WotexLabWorkbenchWeb.InvestigationCompletionController do
  @moduledoc """
  Loopback-only, non-streaming OpenAI-compatible bridge from BeamLens/BAML to
  the explicitly selected WoTEx investigation provider.
  """

  use WotexLabWorkbenchWeb, :controller

  alias WotexLabWorkbench.Investigation.Provider

  @model "wotex-lab-investigation"
  @max_messages 32
  @max_context_bytes 32 * 1_024

  @doc "Completes one bounded internal request or fails closed."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"messages" => messages} = params) do
    with true <- Application.get_env(:wotex_lab_workbench, :beamlens_enabled, false),
         true <- loopback?(conn.remote_ip),
         true <- params["stream"] != true,
         true <- params["model"] in [nil, @model],
         {:ok, messages} <- admit_messages(messages) do
      opts =
        []
        |> maybe_put(:output_schema, output_schema(params["response_format"]))
        |> maybe_put(:response_format, params["response_format"])

      case Provider.complete(messages, opts) do
        {:ok, content, metadata} ->
          json(conn, %{
            id: "wotex-lab-#{System.unique_integer([:positive])}",
            object: "chat.completion",
            created: System.system_time(:second),
            model: metadata.model,
            choices: [
              %{
                index: 0,
                finish_reason: "stop",
                message: %{role: "assistant", content: content}
              }
            ]
          })

        {:error, :diagnostics_unavailable} ->
          conn
          |> put_status(:service_unavailable)
          |> json(%{error: %{message: "investigation providers unavailable"}})
      end
    else
      false ->
        refuse(conn, :forbidden, "investigation bridge is disabled or request is not admitted")

      {:error, :invalid_messages} ->
        refuse(conn, :unprocessable_entity, "messages are not admitted")
    end
  end

  def create(conn, _params), do: refuse(conn, :unprocessable_entity, "messages are not admitted")

  defp admit_messages(messages)
       when is_list(messages) and length(messages) in 1..@max_messages do
    with {:ok, normalized} <- normalize_messages(messages),
         {:ok, encoded} <- Jason.encode(normalized),
         true <- byte_size(encoded) <= @max_context_bytes do
      {:ok, normalized}
    else
      _invalid -> {:error, :invalid_messages}
    end
  end

  defp admit_messages(_messages), do: {:error, :invalid_messages}

  defp normalize_messages(messages) do
    Enum.reduce_while(messages, {:ok, []}, fn
      %{"role" => role, "content" => content}, {:ok, result}
      when role in ["system", "user", "assistant"] ->
        case normalize_content(content) do
          {:ok, admitted} -> {:cont, {:ok, [%{"role" => role, "content" => admitted} | result]}}
          :error -> {:halt, :error}
        end

      _message, _result ->
        {:halt, :error}
    end)
    |> case do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      :error -> :error
    end
  end

  defp normalize_content(content) when is_binary(content), do: {:ok, content}

  defp normalize_content(content) when is_list(content) and length(content) <= 32 do
    Enum.reduce_while(content, {:ok, []}, fn
      %{"type" => "text", "text" => text}, {:ok, result} when is_binary(text) ->
        {:cont, {:ok, [%{"type" => "text", "text" => text} | result]}}

      _block, _result ->
        {:halt, :error}
    end)
    |> case do
      {:ok, blocks} -> {:ok, Enum.reverse(blocks)}
      :error -> :error
    end
  end

  defp normalize_content(_content), do: :error

  defp output_schema(%{"type" => "json_schema", "json_schema" => %{"schema" => schema}})
       when is_map(schema),
       do: schema

  defp output_schema(_format), do: nil
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_address), do: false

  defp refuse(conn, status, message) do
    conn |> put_status(status) |> json(%{error: %{message: message}})
  end
end
