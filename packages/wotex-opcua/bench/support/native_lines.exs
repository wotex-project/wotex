defmodule Wotex.OPCUA.Bench.NativeLines do
  @moduledoc false

  # Request parameters and response lines of the native JSON-line protocol
  # for one Read, one Browse page and one Session open. Credential envelopes
  # carry synthetic bytes of typical DER sizes; no file is read.

  alias Wotex.OPCUA.Bench.Values

  @generation 7
  @namespaces ["http://opcfoundation.org/UA/", "urn:example:opcua:server"]

  @spec generation() :: pos_integer()
  def generation, do: @generation

  @spec inputs() :: %{String.t() => map()}
  def inputs do
    %{
      "read (Double DataValue)" =>
        input("11", "read", read_parameters(), Values.native_data_value("Double", false, 21.5)),
      "browse (64 references)" => input("12", "browse", browse_parameters(), browse_result(64)),
      "open (32 namespaces)" =>
        input("13", "open", open_parameters(), %{
          "session_timeout_ms" => 60_000,
          "namespace_array" => namespaces(32),
          "session_generation" => @generation
        })
    }
  end

  defp input(id, operation, parameters, result) do
    envelope = %{
      "version" => 1,
      "generation" => @generation,
      "id" => id,
      "ok" => true,
      "result" => result
    }

    {:ok, json} = Wotex.JSON.encode(envelope)
    %{id: id, operation: operation, parameters: parameters, response: json <> "\n"}
  end

  defp read_parameters,
    do: %{"node_id" => "ns=2;s=plant/line-4/oven-2/temperature", "index_range" => nil}

  defp browse_parameters do
    %{
      "node_id" => "ns=2;s=plant/line-4",
      "reference_type_id" => "ns=0;i=33",
      "direction" => "forward",
      "include_subtypes" => true,
      "node_class_mask" => 0,
      "page_size" => 256
    }
  end

  defp open_parameters do
    %{
      "endpoint" => "opc.tcp://plc.example:4840",
      "security_policy" => "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",
      "security_mode" => "SignAndEncrypt",
      "client_uri" => "urn:example:opcua:client",
      "server_uri" => "urn:example:opcua:server",
      "certificate" => envelope(1, 1100),
      "private_key" => envelope(2, 1220),
      "server_certificate" => envelope(3, 1100),
      "trust_certificate" => envelope(4, 900),
      "crl" => envelope(5, 480),
      "authentication" => %{"type" => "anonymous"},
      "session_timeout_ms" => 60_000
    }
  end

  defp envelope(seed, size) do
    bytes = <<seed>> <> hd(Values.byte_strings(1, size - 1))
    %{"type" => "bytes", "base64" => Base.encode64(bytes)}
  end

  defp browse_result(count) do
    %{
      "status" => 0,
      "continuation" => nil,
      "references" => Enum.map(1..count, &reference/1)
    }
  end

  defp reference(index) do
    %{
      "reference_type_id" => "ns=0;i=47",
      "is_forward" => true,
      "node_id" => expanded("ns=2;s=plant/line-4/signal-#{index}"),
      "browse_name" => %{"namespace" => 2, "name" => "signal-#{index}"},
      "display_name" => %{"locale" => "en", "text" => "Signal #{index}"},
      "node_class" => 2,
      "type_definition" => expanded("ns=0;i=63")
    }
  end

  defp expanded(node_id), do: %{"node_id" => node_id, "namespace_uri" => nil, "server_index" => 0}

  defp namespaces(count),
    do: @namespaces ++ Enum.map(3..count//1, &"urn:example:opcua:namespace:#{&1}")
end
