# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Runtime.Transport) do
  defmodule Wotex.Lab.Adapters.Runtime.Loopback do
    @moduledoc """
    In-BEAM `Wotex.Runtime.Transport` that talks to a simulated Thing host.

    The transport carries real runtime requests to a `Wotex.Lab.Reference.Thing`
    process, returns the host's immutable results, and delivers host samples and
    events as raw frames that the owning subscription decodes through
    `decode_frame/3`. A linked session process makes host death observable as a
    transport exit. It is a transport reference for exercising the runtime seam;
    it is not evidence that HTTP or MQTT work.

    Configuration: `%{host: pid}`.
    """

    @behaviour Wotex.Runtime.Transport

    alias Wotex.Lab.Adapters.Runtime.Loopback.Session
    alias Wotex.Lab.Error
    alias Wotex.Lab.Reference.Thing
    alias Wotex.Lab.Telemetry
    alias Wotex.Runtime.{ExecutionContext, Request}

    @impl Wotex.Runtime.Transport
    def request(%Request{} = request, %ExecutionContext{} = context, %{host: host})
        when is_pid(host) do
      Telemetry.span(:runtime, :request, %{operation: request.operation, profile: :loopback}, fn ->
        Thing.request(host, request, context.credential)
      end)
    end

    def request(_, _, _), do: {:error, invalid_config()}

    @impl Wotex.Runtime.Transport
    def subscribe(%Request{} = request, owner, %ExecutionContext{} = context, %{host: host})
        when is_pid(owner) and is_pid(host) do
      metadata = %{operation: request.operation, profile: :loopback}

      Telemetry.span(:runtime, :subscription, metadata, fn ->
        with {:ok, reference} <- Thing.subscribe(host, request, owner, context.credential) do
          {:ok, {reference, Session.start(host)}}
        end
      end)
    end

    def subscribe(_, _, _, _), do: {:error, invalid_config()}

    @impl Wotex.Runtime.Transport
    def unsubscribe({reference, session}, %Request{}, %ExecutionContext{}, %{host: host})
        when is_pid(host) do
      :ok = Session.close(session)
      Thing.unsubscribe(host, reference)
    end

    def unsubscribe(_, _, _, _), do: {:error, invalid_config()}

    @impl Wotex.Runtime.Transport
    def decode_frame({:sample, name, value, meta}, %Request{}, _) when is_map(meta) do
      {:ok, value, Map.merge(meta, %{affordance_type: :property, affordance_name: name})}
    end

    def decode_frame({:event, name, payload, meta}, %Request{}, _) when is_map(meta) do
      {:ok, payload, Map.merge(meta, %{affordance_type: :event, affordance_name: name})}
    end

    def decode_frame(:keepalive, %Request{}, _), do: :ignore

    def decode_frame(_, %Request{}, _) do
      {:error,
       Error.new(:invalid_frame, :transport, "loopback host delivered an unknown frame",
         class: :protocol
       )}
    end

    defp invalid_config do
      Error.new(:invalid_transport_config, :transport, "loopback transport requires a host pid",
        class: :permanent
      )
    end
  end
end
