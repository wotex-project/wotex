defmodule Wotex.Matter.Bridge.Wire do
  @moduledoc """
  Decodes bounded native bridge requests and encodes correlated consumer results.

  This version-1 `matter-bridge` role is separate from the controller protocol.
  `decode_request/2` requires one complete LF-delimited frame and the expected
  16-byte process generation. It preserves the complete CASE/group principal,
  admission-time fabric snapshot, opaque Thing identity, exact path, flags and
  payload. Duplicate, extra and missing fields, unsupported cells and malformed
  values return `Wotex.Matter.Error` without including external data.

  Requests contain inert native metadata. `:deadline_native_ms` belongs to the
  native elapsed-time clock; it cannot be compared directly with BEAM time.
  Decoding performs no host authentication, live fabric/ACL lookup, deadline
  projection, consumer authorization or ExposedThing dispatch. The process and
  policy owner supplies those boundaries before executing a request.

  Read payloads are `nil`. The four finite scalar writes retain `{:u16, value}`
  or `{:nullable_enum8, value}`; null remains explicit. Invoke payloads retain
  `{:tlv, bytes}` with one anonymous Structure root, at most 65536 bytes, 24
  container levels and 4096 nodes including the root. The scan enforces SDK
  tag/container rules without an implicit profile. It leaves command fields,
  profile identifiers and scalar values opaque for the selected consumer
  mapping. It does not apply the narrower controller TLV representation profile.

  Encoding a result neither proves consumer authorization nor establishes SDK
  completion or a physical effect. These pure functions start no process and
  perform no I/O, clock sampling or custody mutation.
  """

  alias Wotex.Matter.Bridge.{Arguments, Path}
  alias Wotex.Matter.Error

  @keys ~w(v backend type generation id deadline_ms thing operation path principal fabric_scope flags list data_version payload)
  @limits [
    max_bytes: 262_143,
    max_depth: 3,
    max_nodes: 128,
    max_collection_size: 16,
    max_string_bytes: 131_072
  ]
  @uint64 0xFFFFFFFFFFFFFFFF
  @operation %{"read" => :read, "write" => :write, "invoke" => :invoke}
  @auth_mode %{"case" => :case, "group" => :group}
  @outcome %{completed: "completed", denied: "denied", failed: "failed", unknown: "unknown"}

  @typedoc "An inert request retaining native scope, clock deadline and owned payload bytes."
  @type request :: %{
          generation: binary(),
          id: pos_integer(),
          deadline_native_ms: pos_integer(),
          thing: binary(),
          operation: :read | :write | :invoke,
          path: %{endpoint: pos_integer(), cluster: non_neg_integer(), member: non_neg_integer()},
          principal: %{
            fabric_index: pos_integer(),
            auth_mode: :case | :group,
            subject: non_neg_integer(),
            cats: [non_neg_integer()],
            is_commissioning: boolean()
          },
          fabric_scope: %{
            epoch: pos_integer(),
            fabric_id: pos_integer(),
            bridge_node: pos_integer(),
            root_public_key: binary(),
            noc_sha256: binary()
          },
          flags: %{
            expanded: boolean(),
            timed: boolean(),
            fabric_filtered: boolean(),
            allows_large_payload: boolean()
          },
          list: %{operation: :not_list, index: 0},
          data_version: non_neg_integer() | nil,
          payload:
            nil | {:u16, non_neg_integer()} | {:nullable_enum8, nil | 0..2} | {:tlv, binary()}
        }

  @doc "Decodes one request frame of at most 262144 bytes including its final LF."
  @spec decode_request(term(), term()) :: {:ok, request()} | {:error, Error.t()}
  def decode_request(frame, generation)
      when is_binary(frame) and byte_size(frame) in 1..262_144 and
             is_binary(generation) and byte_size(generation) == 16 do
    with true <- :binary.last(frame) == 10,
         body = binary_part(frame, 0, byte_size(frame) - 1),
         :nomatch <- :binary.match(body, ["\n", "\r", <<0>>]),
         {:ok, value} <- Wotex.JSON.decode(body, @limits),
         true <- exact?(value, @keys),
         true <-
           value["v"] === 1 and value["backend"] === "matter-bridge" and value["type"] === "request",
         true <- value["generation"] === Base.encode16(generation, case: :lower),
         {:ok, id} <- uint64(value["id"], 1),
         {:ok, deadline} <- uint64(value["deadline_ms"], 1),
         {:ok, thing} <- hex(value["thing"], 1, 256),
         {:ok, operation} <- Map.fetch(@operation, value["operation"]),
         {:ok, path} <- path(value["path"], operation),
         {:ok, principal} <- principal(value["principal"]),
         {:ok, fabric} <- fabric(value["fabric_scope"]),
         {:ok, flags} <- flags(value["flags"], operation),
         true <- value["list"] === %{"operation" => "not-list", "index" => 0},
         true <- data_version?(value["data_version"], operation),
         {:ok, payload} <- payload(value["payload"], operation, path) do
      {:ok,
       %{
         generation: generation,
         id: id,
         deadline_native_ms: deadline,
         thing: thing,
         operation: operation,
         path: path,
         principal: principal,
         fabric_scope: fabric,
         flags: flags,
         list: %{operation: :not_list, index: 0},
         data_version: value["data_version"],
         payload: payload
       }}
    else
      _ -> invalid()
    end
  end

  def decode_request(_, _), do: invalid()

  @doc "Encodes one exact six-field result with LF, a nonzero uint64 ID and a fixed outcome."
  @spec encode_result(term(), term(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode_result(generation, id, outcome)
      when is_binary(generation) and byte_size(generation) == 16 and is_integer(id) and
             id in 1..@uint64 do
    with {:ok, selected} <- Map.fetch(@outcome, outcome),
         {:ok, bytes} <-
           Jason.encode(%{
             "v" => 1,
             "backend" => "matter-bridge",
             "type" => "result",
             "generation" => Base.encode16(generation, case: :lower),
             "id" => Integer.to_string(id),
             "outcome" => selected
           }),
         true <- byte_size(bytes) < 512 do
      {:ok, bytes <> "\n"}
    else
      _ -> invalid()
    end
  end

  def encode_result(_, _, _), do: invalid()

  defp exact?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
  defp unsigned?(value, maximum), do: is_integer(value) and value >= 0 and value <= maximum

  defp uint64(value, minimum) when is_binary(value) and byte_size(value) in 1..20 do
    if Regex.match?(~r/\A(?:0|[1-9][0-9]*)\z/, value) do
      integer = String.to_integer(value)
      if integer in minimum..@uint64, do: {:ok, integer}, else: :error
    else
      :error
    end
  end

  defp uint64(_, _), do: :error

  defp hex(value, minimum, maximum) when is_binary(value) do
    if byte_size(value) >= minimum * 2 and byte_size(value) <= maximum * 2 and
         rem(byte_size(value), 2) == 0 and Regex.match?(~r/\A[0-9a-f]*\z/, value),
       do: Base.decode16(value, case: :lower),
       else: :error
  end

  defp hex(_, _, _), do: :error

  defp path(value, operation) do
    if exact?(value, ~w(endpoint cluster member)) and
         Path.valid?(value["endpoint"], value["cluster"], value["member"], operation),
       do:
         {:ok, %{endpoint: value["endpoint"], cluster: value["cluster"], member: value["member"]}},
       else: :error
  end

  defp principal(value) do
    with true <- exact?(value, ~w(fabric_index auth_mode subject cats is_commissioning)),
         true <- unsigned?(value["fabric_index"], 254) and value["fabric_index"] >= 1,
         {:ok, auth} <- Map.fetch(@auth_mode, value["auth_mode"]),
         {:ok, subject} <- uint64(value["subject"], 0),
         cats when is_list(cats) and length(cats) == 3 <- value["cats"],
         true <- Enum.all?(cats, &unsigned?(&1, 0xFFFFFFFF)),
         true <- is_boolean(value["is_commissioning"]) do
      {:ok,
       %{
         fabric_index: value["fabric_index"],
         auth_mode: auth,
         subject: subject,
         cats: cats,
         is_commissioning: value["is_commissioning"]
       }}
    else
      _ -> :error
    end
  end

  defp fabric(value) do
    with true <- exact?(value, ~w(epoch fabric_id bridge_node root_public_key noc_sha256)),
         {:ok, epoch} <- uint64(value["epoch"], 1),
         {:ok, id} <- uint64(value["fabric_id"], 1),
         {:ok, node} <- uint64(value["bridge_node"], 1),
         true <- node <= 0xFFFFFFEFFFFFFFFF,
         {:ok, <<4, _::binary>> = root} <- hex(value["root_public_key"], 65, 65),
         {:ok, digest} <- hex(value["noc_sha256"], 32, 32) do
      {:ok,
       %{epoch: epoch, fabric_id: id, bridge_node: node, root_public_key: root, noc_sha256: digest}}
    else
      _ -> :error
    end
  end

  defp flags(value, operation) do
    if exact?(value, ~w(expanded timed fabric_filtered allows_large_payload)) and
         Enum.all?(Map.values(value), &is_boolean/1) and flags_cell?(value, operation),
       do:
         {:ok,
          %{
            expanded: value["expanded"],
            timed: value["timed"],
            fabric_filtered: value["fabric_filtered"],
            allows_large_payload: value["allows_large_payload"]
          }},
       else: :error
  end

  defp flags_cell?(value, :read), do: not value["timed"]

  defp flags_cell?(value, :write),
    do: not value["fabric_filtered"] and not value["allows_large_payload"]

  defp flags_cell?(value, :invoke),
    do: not value["expanded"] and not value["fabric_filtered"] and not value["allows_large_payload"]

  defp data_version?(nil, _), do: true
  defp data_version?(value, :write), do: unsigned?(value, 0xFFFFFFFF)
  defp data_version?(_, _), do: false
  defp payload(nil, :read, _), do: {:ok, nil}

  defp payload(value, :write, path) do
    with true <- exact?(value, ~w(kind value)),
         true <- write_value?(value, path) do
      kind = if value["kind"] == "u16", do: :u16, else: :nullable_enum8
      {:ok, {kind, value["value"]}}
    else
      _ -> :error
    end
  end

  defp payload(value, :invoke, _) do
    with true <- exact?(value, ~w(kind value)) and value["kind"] === "tlv",
         {:ok, bytes} <- hex(value["value"], 2, 65_536),
         true <- Arguments.valid?(bytes) do
      {:ok, {:tlv, bytes}}
    else
      _ -> :error
    end
  end

  defp payload(_, _, _), do: :error

  defp write_value?(%{"kind" => "u16", "value" => value}, path),
    do:
      unsigned?(value, 65_535) and
        ((path.cluster == 3 and path.member == 0) or
           (path.cluster == 6 and path.member in [0x4001, 0x4002]))

  defp write_value?(%{"kind" => "nullable_enum8", "value" => value}, path),
    do: path.cluster == 6 and path.member == 0x4003 and (is_nil(value) or unsigned?(value, 2))

  defp write_value?(_, _), do: false
  defp invalid, do: {:error, Error.new(:invalid_frame)}
end
