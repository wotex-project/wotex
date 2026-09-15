defmodule Wotex.CoAP.SecurityOSCORETest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.CoAP.{Error, Security}

  defp credential do
    %{
      mode: :oscore,
      master_secret: <<0::128>>,
      master_salt: <<>>,
      sender_id: <<>>,
      recipient_id: <<1>>,
      context_store: "/private/var/lib/wotex-oscore"
    }
  end

  test "WCO-S06 constructs a redacted fixed-suite OSCORE credential without filesystem access" do
    store =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-absent-store-#{System.unique_integer([:positive])}"
      )

    input = %{credential() | context_store: store}
    refute File.exists?(store)

    assert {:ok, value} = Security.new(input)
    assert value.id_context == nil
    assert value.master_secret == input.master_secret
    assert value.master_salt == <<>>
    assert value.sender_id == <<>>
    assert value.recipient_id == <<1>>
    assert value.context_store == input.context_store
    assert :ok = Security.validate(value)
    assert {:ok, ^value} = Security.new(Map.to_list(input))
    assert inspect(value) == "#Wotex.CoAP.Security<mode: :oscore, ...>"
    refute inspect(value) =~ input.context_store

    assert {:ok, explicit_nil} = Security.new(Map.put(input, :id_context, nil))
    assert explicit_nil == value
    refute File.exists?(store)
  end

  test "WCO-C02 WCO-S06 accepts exact OSCORE byte and path boundaries" do
    for values <- [
          %{
            credential()
            | master_secret: :binary.copy(<<1>>, 16),
              master_salt: <<>>,
              sender_id: <<>>,
              recipient_id: :binary.copy(<<2>>, 7),
              context_store: "/"
          },
          credential()
          |> Map.merge(%{
            master_secret: :binary.copy(<<1>>, 32),
            master_salt: :binary.copy(<<2>>, 32),
            sender_id: :binary.copy(<<3>>, 7),
            recipient_id: <<>>,
            id_context: :binary.copy(<<4>>, 255),
            context_store: "/" <> String.duplicate("a", 4095)
          }),
          Map.put(credential(), :id_context, <<>>)
        ] do
      assert {:ok, value} = Security.new(values)
      assert :ok = Security.validate(value)
    end
  end

  test "WCO-C02 WCO-S06 rejects malformed OSCORE material without disclosing it" do
    private = "PRIVATE-OSCORE-CANARY"
    input = %{credential() | master_secret: private}

    invalid = [
      Map.put(input, :master_secret, :binary.copy(<<0>>, 15)),
      Map.put(input, :master_secret, :binary.copy(<<0>>, 33)),
      Map.put(input, :master_secret, nil),
      Map.put(input, :master_salt, :binary.copy(<<0>>, 33)),
      Map.put(input, :master_salt, nil),
      Map.put(input, :sender_id, :binary.copy(<<0>>, 8)),
      Map.put(input, :recipient_id, :binary.copy(<<0>>, 8)),
      Map.put(input, :sender_id, input.recipient_id),
      Map.put(input, :id_context, :binary.copy(<<0>>, 256)),
      Map.put(input, :id_context, false),
      Map.put(input, :context_store, "relative/path"),
      Map.put(input, :context_store, "/private/\0store"),
      Map.put(input, :context_store, <<47, 255>>),
      Map.put(input, :context_store, "/" <> String.duplicate("a", 4096)),
      Map.put(input, :algorithm, :aes_ccm_16_64_128),
      Map.delete(input, :context_store),
      Map.delete(input, :master_salt),
      [
        mode: :oscore,
        master_secret: input.master_secret,
        master_secret: input.master_secret,
        master_salt: input.master_salt,
        sender_id: input.sender_id,
        recipient_id: input.recipient_id,
        context_store: input.context_store
      ]
    ]

    for values <- invalid do
      assert {:error, %Error{code: :invalid_security, details: %{}} = error} =
               Security.new(values)

      refute inspect(error) =~ private
    end
  end

  test "WCO-C02 WCO-S06 forged or cross-mode credential structs fail revalidation" do
    {:ok, value} = Security.new(credential())

    for bad <- [
          nil,
          credential(),
          Map.put(value, :extra, true),
          %{value | master_secret: <<0>>},
          %{value | sender_id: value.recipient_id},
          %{value | context_store: "relative"},
          %{value | mode: :unknown}
        ] do
      assert {:error, %Error{code: :invalid_security}} = Security.validate(bad)
    end
  end

  property "WCO-C02 WCO-S06 OSCORE byte bounds have deterministic admission" do
    check all(
            secret <- binary(max_length: 40),
            salt <- binary(max_length: 40),
            sender <- binary(max_length: 10),
            recipient <- binary(max_length: 10),
            context <- one_of([constant(nil), binary(max_length: 260)])
          ) do
      input = %{
        mode: :oscore,
        master_secret: secret,
        master_salt: salt,
        sender_id: sender,
        recipient_id: recipient,
        id_context: context,
        context_store: "/fixture/context"
      }

      result = Security.new(input)
      assert result == Security.new(Map.to_list(input))

      if byte_size(secret) in 16..32 and byte_size(salt) in 0..32 and
           byte_size(sender) in 0..7 and byte_size(recipient) in 0..7 and sender != recipient and
           (is_nil(context) or byte_size(context) in 0..255) do
        assert {:ok, value} = result
        assert :ok = Security.validate(value)
      else
        assert {:error, %Error{code: :invalid_security}} = result
      end
    end
  end
end
