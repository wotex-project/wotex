defmodule Wotex.Thread.CoapClient do
  @moduledoc false

  alias Wotex.CoAP

  @spec run([String.t()]) :: :ok | no_return()
  def run([sensor_address, light_address, result_path]) do
    sensor = exchange(sensor_address, fn session -> CoAP.get(session, "/sensor/temperature") end)

    light =
      with_session(light_address, fn session ->
        %{
          "before" => observe(CoAP.get(session, "/light/on_off")),
          "put" => observe(CoAP.put(session, "/light/on_off", "1", content_format: :text)),
          "after" => observe(CoAP.get(session, "/light/on_off"))
        }
      end)

    result = %{
      "format" => "wotex.thread.coap-composition",
      "version" => 1,
      "sensor" => sensor,
      "light" => light
    }

    File.write!(result_path, Jason.encode!(result), [:exclusive, :sync])
  end

  def run(_), do: raise("expected sensor address, light address and result path")

  defp exchange(address, operation), do: with_session(address, &observe(operation.(&1)))

  defp with_session(address, operation) do
    {:ok, session} = CoAP.connect(host: address, port: 5683, timeout: 10_000, ack_timeout: 500)

    try do
      operation.(session)
    after
      :ok = CoAP.disconnect(session)
    end
  end

  defp observe({:ok, message}) do
    %{
      "code" => message.code,
      "content_format" => content_format(message.options),
      "payload" => message.payload
    }
  end

  defp observe({:error, error}), do: raise("CoAP exchange failed: #{inspect(error)}")

  defp content_format(options) do
    case List.keyfind(options, 12, 0) do
      {12, <<>>} -> 0
      {12, bytes} -> :binary.decode_unsigned(bytes)
      nil -> nil
    end
  end
end

Wotex.Thread.CoapClient.run(System.argv())
