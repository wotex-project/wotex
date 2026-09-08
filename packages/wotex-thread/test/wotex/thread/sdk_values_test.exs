defmodule Wotex.Thread.SdkValuesTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.Thread.OpenThread.Config
  alias Wotex.Thread.State

  @moduletag requirements: ["WTH-S03", "WTH-N01", "WTH-C02"], vectors: ["WTH-V04"]
  @state %{
    role: :disabled,
    network_name: nil,
    rloc16: nil,
    ipv6_enabled: false,
    thread_enabled: false,
    generation: 0
  }

  test "WTH-S03 WTH-V04 state snapshots retain unavailable, false and zero values" do
    assert {:ok, state} = State.new(@state)
    assert Map.from_struct(state) == @state
    assert :ok = State.validate(state)
    assert {:ok, locator_zero} = State.new(%{@state | rloc16: 0, network_name: "network"})
    assert locator_zero.rloc16 == 0
    assert {:ok, _} = State.new(%{@state | ipv6_enabled: true})

    for role <- [:detached, :child, :router, :leader] do
      assert {:ok, state} =
               State.new(%{@state | role: role, ipv6_enabled: true, thread_enabled: true})

      assert state.role == role
    end
  end

  test "WTH-S03 WTH-V04 forged and inconsistent snapshots fail without retaining their inputs" do
    {:ok, state} = State.new(@state)

    invalid = [
      {:role, :unknown},
      {:role, "leader"},
      {:network_name, ""},
      {:network_name, String.duplicate("n", 17)},
      {:network_name, <<255>>},
      {:network_name, "secret\0canary"},
      {:network_name, 1},
      {:rloc16, -1},
      {:rloc16, 65_536},
      {:rloc16, "0"},
      {:ipv6_enabled, 0},
      {:thread_enabled, true},
      {:thread_enabled, :yes},
      {:generation, -1},
      {:generation, "0"}
    ]

    for {field, value} <- invalid do
      assert {:error, error} = State.new(Map.put(@state, field, value))
      assert error.code == :invalid_state
      refute inspect(error) =~ "secret"
      assert {:error, _} = State.validate(Map.put(state, field, value))
    end

    assert {:error, _} = State.new(%{@state | role: :child})
    assert {:error, _} = State.new(Map.put(@state, :secret, "canary"))
    assert {:error, _} = State.new(Map.put(Map.delete(@state, :role), :secret, "canary"))
    assert {:error, _} = State.new([])
    assert {:error, _} = State.validate(Map.put(state, :secret, "canary"))
    assert {:error, _} = State.validate(Map.put(Map.delete(state, :role), :secret, "canary"))
    assert {:error, _} = State.validate(nil)
  end

  property "WTH-S03 WTH-V04 UTF-8 network names use a byte limit and locators remain exact" do
    check all(
            locator <- integer(0..65_535),
            count <- integer(1..8),
            generation <- integer(0..1_000_000)
          ) do
      values = %{
        @state
        | network_name: String.duplicate("é", count),
          rloc16: locator,
          generation: generation
      }

      assert {:ok, state} = State.new(values)
      assert Map.from_struct(state) == values
    end
  end

  test "WTH-S03 WTH-V04 SDK options require an explicit resource set with no acquisition" do
    for mode <- [:open_existing, :create_new],
        radio <- [
          "spinel+hdlc+uart:///dev/tty-fixture",
          "spinel+hdlc+forkpty:///tmp/fixture-rcp?forkpty-arg=1",
          "spinel+spi:///dev/spidev-fixture"
        ] do
      opts = Keyword.merge(options(), storage_mode: mode, radio_url: radio)
      assert {:ok, config} = Config.new(opts)
      assert config.timeout == 5000
      refute config.allow_network_creation
      assert config.owner == self()
      assert :ok = Config.validate(config)
    end

    assert {:ok, config} = Config.new(options() ++ [timeout: 60_000, allow_network_creation: true])
    assert config.timeout == 60_000
    assert config.allow_network_creation
  end

  test "WTH-S03 WTH-V04 SDK option validation rejects malformed structures and conceals configuration" do
    assert {:ok, config} = Config.new(options())
    refute inspect(config) =~ "private-canary"

    for {field, value} <- [
          {:executable, "relative"},
          {:executable, "/"},
          {:executable, "/private\0canary"},
          {:executable, <<47, 255>>},
          {:storage_path, String.duplicate("/x", 2049)},
          {:storage_path, nil},
          {:radio_url, "http://example.invalid"},
          {:radio_url, "spinel+hdlc+uart:///"},
          {:radio_url, "spinel+hdlc+uart:///dev/x#fragment"},
          {:radio_url, "spinel+hdlc+uart:///dev/x\n"},
          {:radio_url, <<255>>},
          {:radio_url, 0},
          {:interface, ""},
          {:interface, "a/b"},
          {:interface, ":bad"},
          {:interface, "abcdefghijklmnop"},
          {:interface, nil},
          {:storage_mode, :truncate},
          {:owner, nil},
          {:timeout, 0},
          {:timeout, 60_001},
          {:timeout, "1000"},
          {:allow_network_creation, :yes}
        ] do
      assert {:error, error} = Config.new(Keyword.put(options(), field, value))
      assert error.code == :invalid_options
      refute inspect(error) =~ "private"
      assert {:error, _} = Config.validate(Map.put(config, field, value))
    end

    for input <- [
          nil,
          %{},
          [],
          [:bad],
          [{:owner, self()} | :bad],
          options() ++ options(),
          [{:unknown, true} | options()],
          [{"owner", self()}]
        ] do
      assert {:error, _} = Config.new(input)
    end

    assert {:error, _} = Config.validate(Map.put(config, :unknown, :value))
    assert {:error, _} = Config.validate(Map.put(Map.delete(config, :owner), :unknown, :value))
    assert {:error, _} = Config.validate(nil)
  end

  defp options do
    [
      executable: "/nonexistent/private-canary/bridge",
      radio_url: "spinel+hdlc+uart:///nonexistent/private-canary/radio",
      interface: "wth-fixture",
      storage_path: "/nonexistent/private-canary/store",
      storage_mode: :create_new,
      owner: self()
    ]
  end
end
