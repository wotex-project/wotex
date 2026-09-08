defmodule Wotex.BACnet.CStackTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet
  alias Wotex.BACnet.IPv4
  @moduletag :interop

  test "independent C stack acknowledges read/write and rejects an unknown object" do
    port = System.fetch_env!("WOTEX_BACNET_INTEROP_PORT") |> String.to_integer()

    assert {:ok, session} =
             BACnet.connect(
               client: IPv4,
               local_ip: :none,
               local_port: 55_812,
               destination: {{127, 0, 0, 1}, port},
               timeout: 3000
             )

    message = %{
      type: :read_property,
      object_type: :analog_output,
      instance: 1,
      property: :present_value
    }

    try do
      assert {:ok, %Encoding{} = original} = BACnet.send(session, message)

      assert {:ok, :written} =
               BACnet.send(
                 session,
                 Map.merge(
                   message,
                   %{type: :write_property, priority: 16, value: Encoding.create!({:real, 42.5})}
                 )
               )

      assert {:ok, %Encoding{type: :real, value: 42.5}} = BACnet.send(session, message)

      assert {:ok, :written} =
               BACnet.send(
                 session,
                 Map.merge(
                   message,
                   %{type: :write_property, priority: 16, value: original}
                 )
               )

      assert {:error, %{code: :remote_error}} =
               BACnet.send(session, %{message | instance: 4_194_000})
    after
      BACnet.disconnect(session)
    end
  end
end
