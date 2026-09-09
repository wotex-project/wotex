defmodule WotexLabWorkbench.Investigation.Config do
  @moduledoc """
  Builds the explicit Workbench configuration for its local BeamLens provider bridge.

  `client_registry/0` reads required reference-host settings, admits the listed
  provider choices and validates a plain HTTP URL with a loopback host name.
  Missing required settings raise; invalid supplied values return tagged
  errors. Each successful call generates a private random capability for the
  bridge registry. The caller owns its lifetime and must not publish the
  returned capability or registry as diagnostics.
  """

  @app :wotex_lab_workbench

  @doc "Builds BeamLens's registry and a private bridge capability."
  @spec client_registry() ::
          {:ok, map()} | {:error, :invalid_bridge_url | :provider_not_selected}
  def client_registry do
    url = Application.fetch_env!(@app, :beamlens_bridge_url)
    provider = Application.fetch_env!(@app, :beamlens_provider)

    cond do
      not loopback_url?(url) ->
        {:error, :invalid_bridge_url}

      provider not in [:codex_then_ollama, :ollama] ->
        {:error, :provider_not_selected}

      true ->
        capability = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

        {:ok,
         %{
           capability: capability,
           registry: %{
             primary: "WotexLabInvestigation",
             clients: [
               %{
                 name: "WotexLabInvestigation",
                 provider: "openai-generic",
                 options: %{
                   api_key: capability,
                   base_url: url,
                   model: "wotex-lab-investigation"
                 }
               }
             ]
           }
         }}
    end
  end

  @doc "Whether a URL is plain HTTP on an exact loopback host with no userinfo/query/fragment."
  @spec loopback_url?(term()) :: boolean()
  def loopback_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "http", host: host, port: port, userinfo: nil, query: nil, fragment: nil}
      when host in ["127.0.0.1", "localhost", "::1"] and is_integer(port) ->
        true

      _other ->
        false
    end
  end

  def loopback_url?(_url), do: false
end
