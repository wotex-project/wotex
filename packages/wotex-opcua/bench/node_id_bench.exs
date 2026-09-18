alias Wotex.OPCUA.{Address, Binary}

namespace_uri = "urn:example:opcua:plant"

inputs =
  Map.new(
    %{
      "numeric" => "ns=0;i=2258",
      "string" => "ns=2;s=plant/line-4/oven-2/temperature",
      "GUID" => "ns=3;g=72962b91-fa75-4ae6-8d28-b404dc7daf63"
    },
    fn {label, text} ->
      {:ok, node} = Address.new(text)
      {:ok, bytes} = Binary.encode_node_id(node)
      expanded = %{node_id: %{node | namespace: 0}, namespace_uri: namespace_uri, server_index: 0}
      {:ok, expanded_bytes} = Binary.encode_expanded_node_id(expanded)

      {label,
       %{
         text: text,
         node: node,
         bytes: bytes,
         expanded: expanded,
         expanded_bytes: expanded_bytes
       }}
    end
  )

Benchee.run(
  %{
    "parse NodeId text" => fn %{text: text} -> {:ok, _} = Address.new(text) end,
    "format NodeId text" => fn %{node: node} -> <<"ns=", _::binary>> = Address.to_string(node) end,
    "encode NodeId" => fn %{node: node} -> {:ok, _} = Binary.encode_node_id(node) end,
    "decode NodeId" => fn %{bytes: bytes} -> {:ok, _, <<>>} = Binary.decode_node_id(bytes) end,
    "encode ExpandedNodeId with namespace URI" => fn %{expanded: expanded} ->
      {:ok, _} = Binary.encode_expanded_node_id(expanded)
    end,
    "decode ExpandedNodeId with namespace URI" => fn %{expanded_bytes: bytes} ->
      {:ok, _, <<>>} = Binary.decode_expanded_node_id(bytes)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/node_id.md",
     title: "# OPC UA NodeId and namespace identity",
     description: """
     `Wotex.OPCUA.Address.new/1` and `to_string/1` (standard NodeId text),
     `Wotex.OPCUA.Binary.encode_node_id/1` and `decode_node_id/1` (Part 6
     binary NodeId in its shortest form) and the ExpandedNodeId codecs with an
     explicit namespace URI in place of the namespace index. Inputs are one
     numeric (the Server CurrentTime variable), one string and one GUID
     identifier.
     """}
  ]
)
