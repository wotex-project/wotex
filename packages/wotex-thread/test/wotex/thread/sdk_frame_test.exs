defmodule Wotex.Thread.SdkFrameTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.Thread.{Error, State}
  alias Wotex.Thread.OpenThread.Frame

  @moduletag requirements: ["WTH-S03", "WTH-C07"], vectors: ["WTH-V04"]
  @ready %{
    "version" => 1,
    "event" => "ready",
    "backend" => "openthread",
    "revision" => "f34c5e5476829d9205e80b37fccc2bdfe97e1dab"
  }
  @state %{
    "role" => "disabled",
    "network_name" => nil,
    "rloc16" => nil,
    "ipv6_enabled" => false,
    "thread_enabled" => false,
    "generation" => 1
  }

  test "WTH-C07 ready identity is exact and decoded without creating atoms" do
    assert {:ok, @ready} = Frame.decode(Jason.encode!(@ready))
    assert Frame.ready?(@ready)

    for bad <- [
          nil,
          %{},
          Map.put(@ready, "version", 1.0),
          Map.put(@ready, "version", 2),
          Map.put(@ready, "revision", "unsupported"),
          Map.put(@ready, "extra", true)
        ] do
      refute Frame.ready?(bad)
    end
  end

  test "WTH-C07 malformed JSON, duplicate decoded keys and size limits fail closed" do
    for line <- [
          nil,
          4,
          "",
          "[]",
          "null",
          "{",
          "{} {}",
          "{\"a\":1,\"a\":2}",
          "{\"a\":{\"b\":1,\"\\u0062\":2}}",
          "{\"value\":NaN}",
          "{\"value\":1e999}",
          <<123, 34, 255, 34, 58, 49, 125>>,
          "{\"value\":\"unfinished\\",
          String.duplicate(" ", 131_072),
          "{]",
          "}",
          "]"
        ] do
      assert Frame.decode(line) == :error
    end

    valid = "{\"value\":\"" <> String.duplicate("a", 131_071 - 12) <> "\"}"
    assert byte_size(valid) == 131_071
    assert {:ok, _} = Frame.decode(valid)
    assert :error = Frame.decode(" " <> valid)
  end

  test "WTH-C07 nesting and collection limits precede unbounded JSON recursion" do
    assert {:ok, _} =
             Frame.decode(
               "{\"v\":" <> String.duplicate("[", 7) <> "0" <> String.duplicate("]", 7) <> "}"
             )

    assert :error =
             Frame.decode(
               "{\"v\":" <> String.duplicate("[", 8) <> "0" <> String.duplicate("]", 8) <> "}"
             )

    assert :error = Frame.decode(String.duplicate("[", 60_000))
    assert {:ok, _} = Frame.decode(Jason.encode!(%{"v" => List.duplicate(false, 1024)}))
    assert :error = Frame.decode(Jason.encode!(%{"v" => List.duplicate(false, 1025)}))
    assert {:ok, _} = Frame.decode(Jason.encode!(Map.new(1..1024, &{Integer.to_string(&1), nil})))
    assert :error = Frame.decode(Jason.encode!(Map.new(1..1025, &{Integer.to_string(&1), nil})))
    assert {:ok, _} = Frame.decode(Jason.encode!(%{"v" => "[]{}\"\\"}))

    assert :error =
             Frame.decode(Jason.encode!(%{"v" => List.duplicate(List.duplicate(0, 1024), 4)}))
  end

  test "WTH-S03 exact state values preserve false, zero, nil and every finite role" do
    assert {:ok, %State{role: :disabled, network_name: nil, rloc16: nil, generation: 1}} =
             Frame.response(success(@state), "id", "open")

    for role <- ["detached", "child", "router", "leader"] do
      state = %{
        @state
        | "role" => role,
          "ipv6_enabled" => true,
          "thread_enabled" => true,
          "network_name" => "fixture",
          "rloc16" => 0
      }

      assert {:ok, %State{rloc16: 0} = result} = Frame.response(success(state), "id", "inspect")
      assert Atom.to_string(result.role) == role
    end

    for state <- [
          nil,
          %{},
          Map.put(@state, "role", "invented"),
          Map.put(@state, "generation", 2),
          Map.put(@state, "generation", 1.0),
          Map.put(@state, "extra", nil),
          Map.put(@state, "thread_enabled", true),
          Map.put(@state, "network_name", ""),
          Map.put(@state, "network_name", String.duplicate("é", 9)),
          Map.put(@state, "rloc16", -1)
        ] do
      assert :invalid = Frame.response(success(state), "id", "inspect")
    end
  end

  test "WTH-C07 success envelopes require exact identity and the selected result type" do
    for operation <- ["state", "version", "network_name", "rloc16", "close"] do
      valid =
        %{
          "state" => "disabled",
          "version" => "SDK 1",
          "network_name" => "fixture",
          "rloc16" => 0,
          "close" => nil
        }[operation]

      assert {:ok, ^valid} = Frame.response(success(valid), "id", operation)

      for frame <- [
            Map.put(success(valid), "id", "wrong"),
            Map.put(success(valid), "version", 1.0),
            Map.put(success(valid), "ok", 1),
            Map.delete(success(valid), "result"),
            Map.put(success(valid), "extra", nil)
          ] do
        assert :invalid = Frame.response(frame, "id", operation)
      end
    end

    for operation <- ["network_name", "rloc16"],
        do: assert(Frame.response(success(nil), "id", operation) == {:ok, nil})

    for {value, operation} <- [
          {false, "close"},
          {true, "rloc16"},
          {65_536, "rloc16"},
          {1, "state"},
          {"unknown", "state"},
          {"", "version"},
          {"canary\0secret", "version"},
          {<<255>>, "version"},
          {String.duplicate("a", 1025), "version"},
          {1, "unsupported"}
        ] do
      assert :invalid = Frame.response(success(value), "id", operation)
    end
  end

  test "WTH-C07 failure codes and numeric statuses are bounded without raw SDK text" do
    codes = %{
      "invalid_request" => :invalid_message,
      "storage_unavailable" => :storage_unavailable,
      "interface_in_use" => :interface_in_use,
      "already_open" => :already_open,
      "sdk_start_failed" => :transport_unavailable,
      "not_open" => :connection_closed,
      "not_supported" => :not_supported,
      "invalid_sdk_state" => :invalid_response,
      "io_failed" => :connection_closed,
      "remote_error" => :remote_error
    }

    for {native, expected} <- codes do
      assert {:error, %Error{code: ^expected, details: %{}}} =
               Frame.response(failure(%{"code" => native}), "id", "inspect")
    end

    assert {:error, %Error{code: :remote_error, details: %{status: 65_535}}} =
             Frame.response(
               failure(%{"code" => "remote_error", "status" => 65_535}),
               "id",
               "inspect"
             )

    for error <- [
          nil,
          %{},
          %{"code" => "canary-secret"},
          %{"code" => "not_open", "text" => "secret"},
          %{"code" => "not_open", "status" => 1},
          %{"code" => "remote_error", "status" => -1},
          %{"code" => "remote_error", "status" => 65_536},
          %{"code" => "remote_error", "status" => 1.0},
          %{"code" => "remote_error", "status" => 0, "extra" => "secret"}
        ] do
      assert :invalid = Frame.response(failure(error), "id", "inspect")
    end
  end

  property "WTH-C07 arbitrary bounded bytes never raise or fabricate ready identity" do
    check all(bytes <- binary(max_length: 256)) do
      case Frame.decode(bytes) do
        {:ok, value} -> assert is_map(value)
        :error -> :ok
      end
    end
  end

  defp success(result), do: %{"version" => 1, "id" => "id", "ok" => true, "result" => result}
  defp failure(error), do: %{"version" => 1, "id" => "id", "ok" => false, "error" => error}
end
