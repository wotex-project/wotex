defmodule WotexLabWorkbench.Investigation.Ollama do
  @moduledoc """
  Fixed local fallback for BeamLens explanations.

  It performs one non-streaming OpenAI-compatible request. Preflight requires
  the exact configured model; this module never pulls or selects another one.
  """

  @app :wotex_lab_workbench

  @doc "Completes one bounded diagnostic prompt using the pinned local model."
  @spec complete([map()], keyword()) :: {:ok, String.t(), map()} | {:error, term()}
  def complete(messages, opts \\ []) when is_list(messages) do
    model = config!(:beamlens_ollama_model)
    timeout = Keyword.get(opts, :timeout, config!(:beamlens_ollama_timeout_ms))
    max_tokens = Keyword.get(opts, :max_tokens, config!(:beamlens_ollama_max_tokens))

    body =
      %{
        model: model,
        messages: messages,
        stream: false,
        reasoning_effort: "none",
        max_tokens: max_tokens
      }
      |> maybe_put(:response_format, Keyword.get(opts, :response_format))

    result =
      :telemetry.span(
        [:wotex, :lab, :investigation, :provider],
        %{provider: :ollama, operation: :complete},
        fn ->
          response =
            Req.post(
              config!(:beamlens_ollama_base_url) <> "/chat/completions",
              req_options(json: body, receive_timeout: timeout)
            )

          {response, response_metadata(response)}
        end
      )

    case result do
      {:ok, %{status: 200, body: response}} ->
        case get_in(response, ["choices", Access.at(0), "message", "content"]) do
          content when is_binary(content) and content != "" ->
            {:ok, content, %{provider: :ollama, model: model}}

          _ ->
            {:error, :invalid_ollama_response}
        end

      {:ok, %{status: status}} ->
        {:error, {:ollama_http_status, status}}

      {:error, reason} ->
        {:error, {:ollama_unavailable, inspect(reason, limit: 5, printable_limit: 300)}}
    end
  end

  @doc "Checks that Ollama already serves the exact configured model."
  @spec preflight() :: {:ok, map()} | {:error, term()}
  def preflight do
    result =
      Req.get(
        config!(:beamlens_ollama_base_url) <> "/models",
        req_options(receive_timeout: 2_000)
      )

    case result do
      {:ok, %{status: 200, body: %{"data" => models}}} when is_list(models) ->
        configured = config!(:beamlens_ollama_model)

        if Enum.any?(models, &(&1["id"] == configured)),
          do: {:ok, %{model: configured}},
          else: {:error, {:ollama_model_missing, configured}}

      {:ok, %{status: status}} ->
        {:error, {:ollama_http_status, status}}

      {:error, reason} ->
        {:error, {:ollama_unavailable, inspect(reason, limit: 5, printable_limit: 300)}}
    end
  end

  defp req_options(options) do
    Keyword.merge(
      [retry: false],
      Keyword.merge(options, Application.get_env(@app, :beamlens_req_options, []))
    )
  end

  defp response_metadata({:ok, %{status: status}}), do: %{status: status}
  defp response_metadata({:error, _}), do: %{status: :transport_error}
  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp config!(key), do: Application.fetch_env!(@app, key)
end
