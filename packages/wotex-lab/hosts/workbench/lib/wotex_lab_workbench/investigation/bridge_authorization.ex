defmodule WotexLabWorkbench.Investigation.BridgeAuthorization do
  @moduledoc false

  alias WotexLabWorkbench.Investigation.{Broker, HostedBroker}

  @app :wotex_lab_workbench

  @doc false
  @spec authorize(term()) ::
          {:ok, :codex_then_ollama | :ollama, :local | :hosted}
          | {:error, :bridge_denied}
  def authorize(capability) do
    case Broker.authorize_bridge(capability) do
      :ok ->
        provider = Application.get_env(@app, :beamlens_provider, :none)

        if provider in [:codex_then_ollama, :ollama],
          do: {:ok, provider, :local},
          else: {:error, :bridge_denied}

      {:error, :bridge_denied} ->
        case HostedBroker.authorize_provider(capability) do
          {:ok, provider} -> {:ok, provider, :hosted}
          {:error, :bridge_denied} -> {:error, :bridge_denied}
        end
    end
  end

  @doc false
  @spec record(:local | :hosted, term(), term()) :: :ok
  def record(:hosted, capability, metadata),
    do: HostedBroker.record_provider(capability, metadata)

  def record(:local, _, _), do: :ok
end
