defmodule Wotex.Thread.CommissioningValueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  doctest Wotex.Thread.JoinerIdentity
  doctest Wotex.Thread.JoinerAdmission
  doctest Wotex.Thread.JoinerConfig

  doctest Wotex.Thread.OpenThread.CommissioningValue
  use ExUnitProperties
  alias Wotex.Thread.{Error, JoinerAdmission, JoinerConfig, JoinerIdentity}

  @moduletag requirements: ["WTH-S05", "WTH-C02"], vectors: ["WTH-V08", "WTH-V09"]

  test "commissioner commands have exact shapes and conservative mutation classification" do
    alias Wotex.Thread.OpenThread.{Frame, Request}

    for type <- [:commissioner_start, :commissioner_stop] do
      assert {:ok, {operation, %{}}} = Request.encode(%{type: type})
      assert Request.mutation?(operation)
      assert {:error, %Error{}} = Request.encode(%{type: type, extra: true})
    end

    {:ok, identity} = JoinerIdentity.new(%{eui64: <<42::64>>})
    {:ok, admission} = JoinerAdmission.new(%{identity: identity, pskd: "WTEST123"})

    assert {:ok, {"add_joiner", %{identity: %{value: "000000000000002A"}}}} =
             Request.encode(%{type: :add_joiner, admission: admission})

    assert {:ok, {"remove_joiner", %{identity: %{value: "000000000000002A"}}}} =
             Request.encode(%{type: :remove_joiner, identity: identity})

    for type <- ["add_joiner", "remove_joiner"] do
      assert Request.mutation?(type)
    end

    for code <- [
          "invalid_joiner_identity",
          "invalid_joiner_admission",
          "commissioner_timeout",
          "commissioner_rejected",
          "not_owned",
          "cancelled"
        ] do
      assert {:error, %Error{code: value}} =
               Frame.response(
                 %{"version" => 1, "id" => "1", "ok" => false, "error" => %{"code" => code}},
                 "1",
                 "commissioner_start"
               )

      assert Atom.to_string(value) == code
    end
  end

  test "canonical identity replies and raw standalone requests retain their exact shape" do
    alias Wotex.Thread.OpenThread.{Frame, Request}
    raw = %{eui64: <<42::64>>}
    assert {:ok, %{type: "eui64", value: "000000000000002A"}} = JoinerIdentity.parameters(raw)

    assert {:ok, %{identity: %{value: "000000000000002A"}, lifetime: 60}} =
             JoinerAdmission.parameters(%{identity: raw, pskd: "WTEST123"})

    assert {:error, %Error{}} = JoinerAdmission.parameters(nil)
    assert {:error, %Error{}} = JoinerIdentity.parameters(nil)

    for input <- [raw, %{discerner: %{length: 64, value: 18_446_744_073_709_551_615}}] do
      {:ok, wire} = JoinerIdentity.parameters(input)
      wire = Map.new(wire, fn {key, value} -> {Atom.to_string(key), value} end)
      assert {:ok, ^input} = JoinerIdentity.decode(wire)
    end

    for wire <- [
          nil,
          %{},
          %{"type" => "eui64", "value" => "000000000000002a"},
          %{"type" => "eui64", "value" => "00"},
          %{"type" => "discerner", "length" => 1, "value" => "01"},
          %{"type" => "discerner", "length" => 1, "value" => "+1"},
          %{"type" => "discerner", "length" => 1, "value" => "x"},
          %{"type" => "discerner", "length" => 1, "value" => "2"},
          %{"type" => "discerner", "length" => 64, "value" => "18446744073709551616"}
        ] do
      assert {:error, %Error{}} = JoinerIdentity.decode(wire)
    end

    parameters = %{identity: %{type: "eui64", value: "000000000000002A"}, lifetime: 60}
    assert Request.matches_result?("add_joiner", parameters, %{identity: raw, lifetime_s: 60})
    refute Request.matches_result?("add_joiner", parameters, %{identity: raw, lifetime_s: 1})

    refute Request.matches_result?("add_joiner", parameters, %{
             identity: %{eui64: <<43::64>>},
             lifetime_s: 60
           })

    for result <- [
          %{},
          %{"identity" => nil, "lifetime_s" => 60},
          %{"identity" => %{"type" => "eui64", "value" => "000000000000002A"}, "lifetime_s" => 0}
        ] do
      assert :invalid =
               Frame.response(
                 %{"version" => 1, "id" => "1", "ok" => true, "result" => result},
                 "1",
                 "add_joiner"
               )
    end
  end

  test "identities preserve exact EUI-64 bytes and canonical discerner values" do
    assert {:ok, identity} = JoinerIdentity.new(%{eui64: <<0, 1, 2, 3, 0xFE, 0xFF, 6, 7>>})
    assert {:ok, %{type: "eui64", value: "00010203FEFF0607"}} = JoinerIdentity.encode(identity)

    for length <- 1..64, value <- [0, Bitwise.bsl(1, length) - 1] do
      assert {:ok, identity} = JoinerIdentity.new(%{discerner: %{length: length, value: value}})

      assert {:ok, %{type: "discerner", length: ^length, value: encoded}} =
               JoinerIdentity.encode(identity)

      assert encoded == Integer.to_string(value)

      assert {:error, %Error{code: :invalid_joiner_identity}} =
               JoinerIdentity.new(%{discerner: %{length: length, value: Bitwise.bsl(1, length)}})
    end
  end

  property "all uint64 EUI values round-trip through the exact wire representation" do
    check all(bytes <- binary(length: 8)) do
      assert {:ok, identity} = JoinerIdentity.new(%{eui64: bytes})
      assert {:ok, %{value: encoded}} = JoinerIdentity.encode(identity)
      assert Base.decode16!(encoded) == bytes
    end
  end

  test "wildcards, malformed and forged identities fail without conversions" do
    for input <- [
          nil,
          :any,
          "*",
          %{},
          %{eui64: <<>>},
          %{eui64: <<0::72>>},
          %{eui64: <<0::64>>, extra: true},
          %{discerner: nil},
          %{discerner: %{length: 0, value: 0}},
          %{discerner: %{length: 65, value: 0}},
          %{discerner: %{length: 3, value: -1}},
          %{discerner: %{length: 3, value: 1.0}},
          %{discerner: %{length: 3, value: 0, extra: true}}
        ] do
      assert {:error, %Error{code: :invalid_joiner_identity}} = JoinerIdentity.new(input)
    end

    {:ok, identity} = JoinerIdentity.new(%{eui64: <<0::64>>})

    for value <- [
          nil,
          Map.put(identity, :extra, true),
          %{identity | value: <<>>},
          %{identity | kind: :any},
          %{identity | length: 8}
        ] do
      assert {:error, %Error{}} = JoinerIdentity.encode(value)
    end

    {:ok, identity} = JoinerIdentity.new(%{discerner: %{length: 1, value: 1}})
    assert {:error, %Error{}} = JoinerIdentity.encode(%{identity | value: 2})
  end

  test "admission PSKd has exactly the SDK alphabet and finite lifetime" do
    {:ok, identity} = JoinerIdentity.new(%{eui64: <<0::64>>})

    for byte <- 0..255 do
      input = %{identity: identity, pskd: <<byte, byte, byte, byte, byte, byte>>}

      if byte in ?0..?9 or (byte in ?A..?Y and byte not in [?I, ?O, ?Q]) do
        assert {:ok, %{lifetime: 60} = admission} = JoinerAdmission.new(input)
        assert {:ok, %{lifetime: 60, pskd: pskd}} = JoinerAdmission.encode(admission)
        assert pskd == input.pskd
      else
        assert {:error, %Error{code: :invalid_joiner_admission}} = JoinerAdmission.new(input)
      end
    end

    for lifetime <- [1, 3600], length <- [6, 32] do
      assert {:ok, _} =
               JoinerAdmission.new(%{
                 identity: identity,
                 pskd: String.duplicate("A", length),
                 lifetime: lifetime
               })
    end

    for input <- [
          nil,
          %{identity: nil, pskd: "ABC123"},
          %{identity: identity, pskd: "ABC12"},
          %{identity: identity, pskd: String.duplicate("A", 33)},
          %{identity: identity, pskd: "ABC123", lifetime: 0},
          %{identity: identity, pskd: "ABC123", lifetime: 3601},
          %{identity: identity, pskd: "ABC123", lifetime: 1.0},
          %{identity: identity, pskd: "ABC123", extra: true}
        ] do
      assert {:error, %Error{}} = JoinerAdmission.new(input)
    end

    {:ok, admission} = JoinerAdmission.new(%{identity: identity, pskd: "SECRET123"})
    refute inspect(admission) =~ "SECRET123"

    for invalid <- [nil, Map.put(admission, :extra, true), %{admission | pskd: "bad"}] do
      assert {:error, %Error{}} = JoinerAdmission.encode(invalid)
    end
  end

  test "joiner config bounds UTF-8 fields and redacts credentials and provisioning metadata" do
    {:ok, identity} = JoinerIdentity.new(%{discerner: %{length: 64, value: 42}})

    assert {:ok, config} =
             JoinerConfig.new(%{pskd: "SECRET123", discerner: identity, vendor_data: "private"})

    assert {:ok, %{discerner: %{value: "42"}, pskd: "SECRET123", provisioning_url: nil}} =
             JoinerConfig.encode(config)

    refute inspect(config) =~ "SECRET123"
    refute inspect(config) =~ "private"
    assert {:ok, config} = JoinerConfig.new(%{pskd: "ABC123"})
    assert {:ok, %{discerner: nil}} = JoinerConfig.encode(config)

    for {key, maximum} <- [
          provisioning_url: 64,
          vendor_name: 32,
          vendor_model: 32,
          vendor_sw_version: 32,
          vendor_data: 64
        ] do
      for valid <- [nil, "", String.duplicate("é", div(maximum, 2))] do
        assert {:ok, _} = JoinerConfig.new(Map.put(%{pskd: "ABC123"}, key, valid))
      end

      for invalid <- [:bad, <<0xFF>>, "a\nb", "a\0b", <<127>>, String.duplicate("a", maximum + 1)] do
        assert {:error, %Error{}} = JoinerConfig.new(Map.put(%{pskd: "ABC123"}, key, invalid))
      end
    end

    {:ok, eui} = JoinerIdentity.new(%{eui64: <<0::64>>})

    for invalid <- [
          nil,
          %{},
          %{pskd: "bad"},
          %{pskd: "ABC123", extra: true},
          %{pskd: "ABC123", discerner: eui},
          %{pskd: "ABC123", discerner: :any},
          %{pskd: "ABC123", discerner: %{identity | value: -1}}
        ] do
      assert {:error, %Error{}} = JoinerConfig.new(invalid)
    end

    for invalid <- [nil, Map.put(config, :extra, true), %{config | pskd: "bad"}] do
      assert {:error, %Error{}} = JoinerConfig.encode(invalid)
    end
  end
end
