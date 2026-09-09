defmodule Wotex.OPCUA.Binary.Reference do
  @moduledoc """
  Composes the complete OPC UA ReferenceDescription binary structure.

  `Wotex.OPCUA.Binary` delegates reference encoding and decoding to this pure
  helper. Each reference retains its type, direction, target identity, qualified
  browse name, localized display name, NodeClass and expanded type definition.
  A remote server index or namespace URI remains data; decoding does not follow
  it, open a connection or infer that it belongs to a local Session.

  Encoders require exactly seven atom-keyed fields. NodeClass admits zero and
  the eight individual standard classes, excluding combinations and unknown
  bits. The name and identity codecs enforce their own finite string and numeric
  bounds, so one reference consumes fewer than 1 MiB. Invalid structures return
  `Wotex.OPCUA.Error`; successful decoding returns every unconsumed byte.
  """

  alias Wotex.OPCUA.{Address, Binary, Error}
  alias Wotex.OPCUA.Binary.Names

  @classes [0, 1, 2, 4, 8, 16, 32, 64, 128]
  @type t :: %{
          reference_type_id: Address.t(),
          is_forward: boolean(),
          node_id: Names.expanded_node_id(),
          browse_name: Names.qualified_name(),
          display_name: Names.localized_text(),
          node_class: 0 | 1 | 2 | 4 | 8 | 16 | 32 | 64 | 128,
          type_definition: Names.expanded_node_id()
        }

  @doc "Encodes a validated, full reference in the standard field order."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(
        %{
          reference_type_id: type,
          is_forward: direction,
          node_id: target,
          browse_name: browse,
          display_name: display,
          node_class: class,
          type_definition: definition
        } = value
      )
      when map_size(value) == 7 and class in @classes do
    with {:ok, type} <- Binary.encode_node_id(type),
         {:ok, direction} <- Binary.encode(:boolean, direction),
         {:ok, target} <- Names.encode(:expanded_node_id, target),
         {:ok, browse} <- Names.encode(:qualified_name, browse),
         {:ok, display} <- Names.encode(:localized_text, display),
         {:ok, class} <- Binary.encode(:uint32, class),
         {:ok, definition} <- Names.encode(:expanded_node_id, definition) do
      {:ok, type <> direction <> target <> browse <> display <> class <> definition}
    end
  end

  def encode(_), do: {:error, Error.new(:invalid_value)}

  @doc "Decodes each bounded reference field and rejects unsupported NodeClass values."
  @spec decode(term()) :: {:ok, t(), binary()} | {:error, Error.t()}
  def decode(bytes) do
    with {:ok, type, rest} <- Binary.decode_node_id(bytes),
         {:ok, direction, rest} <- Binary.decode(:boolean, rest),
         {:ok, target, rest} <- Names.decode(:expanded_node_id, rest),
         {:ok, browse, rest} <- Names.decode(:qualified_name, rest),
         {:ok, display, rest} <- Names.decode(:localized_text, rest),
         {:ok, class, rest} <- Binary.decode(:uint32, rest),
         true <- class in @classes,
         {:ok, definition, rest} <- Names.decode(:expanded_node_id, rest) do
      {:ok,
       %{
         reference_type_id: type,
         is_forward: direction,
         node_id: target,
         browse_name: browse,
         display_name: display,
         node_class: class,
         type_definition: definition
       }, rest}
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:invalid_binary)}
    end
  end
end
