defmodule IndependentWritePeer do
  @moduledoc false

  # Independent literal protocol peer. No WoTEx module, helper or fixture is loaded.
  @spec run(String.t(), Path.t()) :: :ok
  def run(mode, trace) do
    File.write!(trace, JSON.encode!(%{"pid" => String.to_integer(System.pid())}) <> "\n")

    emit(%{
      "version" => 1,
      "event" => "ready",
      "backend" => "bluez-native",
      "revision" => "2123ab772fbe97d1369fc9e179ea87c3469cf98f"
    })

    loop(mode, trace)
  end

  defp loop(mode, trace) do
    case line(<<>>) do
      :eof ->
        :ok

      bytes ->
        request = JSON.decode!(bytes)
        File.write!(trace, JSON.encode!(request) <> "\n", [:append])

        if request["event"] == "flow_open" do
          loop(mode, trace)
        else
          case request["operation"] do
            "open" ->
              reply(request["id"], %{
                "generation" => 1,
                "device_path" => "/org/bluez/hci0/device",
                "link_owned" => false,
                "sender" => ":1.42"
              })

              loop(mode, trace)

            "close" ->
              reply(request["id"], nil)

            operation when operation in ["write", "write_command"] ->
              write(request, mode)
              loop(mode, trace)

            _ ->
              failure(request["id"], "not_supported")
              loop(mode, trace)
          end
        end
    end
  end

  defp write(request, "legacy") do
    if request["operation"] == "write_command",
      do: failure(request["id"], "not_supported"),
      else: write(request, "normal")
  end

  defp write(request, mode) do
    true = Enum.sort(Map.keys(request)) == ~w(id operation parameters timeout_ms version)

    %{"address" => address, "value" => %{"type" => "bytes", "base64" => encoded}} =
      request["parameters"]

    true = address["service"] == "0000180f-0000-1000-8000-00805f9b34fb"
    true = address["characteristic"] == "00002a19-0000-1000-8000-00805f9b34fb"
    {:ok, bytes} = Base.decode64(encoded)
    true = byte_size(bytes) <= 512 and Base.encode64(bytes) == encoded

    if mode != "missing_event",
      do: emit(%{"version" => 1, "id" => request["id"], "event" => "write_submitted"})

    if mode == "blocked" do
      :ok
    else
      accepted = %{"write_mode" => "without_response", "evidence" => "native_queue_accepted"}

      value =
        cond do
          request["operation"] == "write" or mode == "ack" -> nil
          mode == "wrong_evidence" -> %{accepted | "evidence" => "acknowledged"}
          mode == "extra" -> Map.put(accepted, "ack", true)
          true -> accepted
        end

      reply(if(mode == "wrong_id", do: "foreign", else: request["id"]), value)
    end
  end

  defp line(bytes) when byte_size(bytes) >= 131_072, do: raise("peer frame bound")

  defp line(bytes) do
    case IO.binread(:stdio, 1) do
      :eof -> :eof
      "\n" -> bytes
      byte when is_binary(byte) -> line(bytes <> byte)
    end
  end

  defp reply(id, value), do: emit(%{"version" => 1, "id" => id, "ok" => true, "result" => value})

  defp failure(id, code),
    do: emit(%{"version" => 1, "id" => id, "ok" => false, "error" => %{"code" => code}})

  defp emit(value), do: IO.binwrite(:stdio, JSON.encode!(value) <> "\n")
end

[mode, trace] = System.argv()
IndependentWritePeer.run(mode, trace)
