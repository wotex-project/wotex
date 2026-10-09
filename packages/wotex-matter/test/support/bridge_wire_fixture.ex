defmodule Wotex.Matter.BridgeWireFixture do
  @moduledoc false

  @generation :binary.copy(<<255>>, 16)
  @spec generation() :: binary()
  def generation, do: @generation

  @spec frame(String.t()) :: map()
  def frame(operation \\ "read") do
    %{
      "v" => 1,
      "backend" => "matter-bridge",
      "type" => "request",
      "generation" => Base.encode16(@generation, case: :lower),
      "id" => "18446744073709551615",
      "deadline_ms" => "18446744073709551615",
      "thing" => "00ff",
      "operation" => operation,
      "path" => %{"endpoint" => 3, "cluster" => 6, "member" => 0},
      "principal" => %{
        "fabric_index" => 254,
        "auth_mode" => "case",
        "subject" => "18446744073709551615",
        "cats" => [1, 0, 0xFFFFFFFF],
        "is_commissioning" => true
      },
      "fabric_scope" => %{
        "epoch" => "18446744073709551615",
        "fabric_id" => "18446744073709551615",
        "bridge_node" => Integer.to_string(0xFFFFFFEFFFFFFFFF),
        "root_public_key" => "04" <> String.duplicate("ff", 64),
        "noc_sha256" => String.duplicate("ff", 32)
      },
      "flags" => %{
        "expanded" => false,
        "timed" => false,
        "fabric_filtered" => false,
        "allows_large_payload" => false
      },
      "list" => %{"operation" => "not-list", "index" => 0},
      "data_version" => nil,
      "payload" => if(operation == "invoke", do: %{"kind" => "tlv", "value" => "1518"}, else: nil)
    }
  end

  @spec encode(map()) :: binary()
  def encode(frame), do: Jason.encode!(frame) <> "\n"

  @spec arguments(binary()) :: map()
  def arguments(bytes), do: %{"kind" => "tlv", "value" => Base.encode16(bytes, case: :lower)}
end
