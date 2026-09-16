defmodule Wotex.OPCUA.Native.FrameTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Error
  alias Wotex.OPCUA.Native.{Frame, Ready}

  test "WOP-X03 owner deadline retains the ready-to-receive delay and caps timeout" do
    ready = %Ready{clock_ms: 50}
    assert {:ok, %{deadline_ms: 60, timeout_ms: 5}} = Frame.admission(ready, 100, 110, 105, 20)
    assert {:ok, %{deadline_ms: 60, timeout_ms: 10}} = Frame.admission(ready, 100, 110, 100, 60_000)

    for now <- [110, 111] do
      assert {:error, %Error{code: :deadline_exceeded}} =
               Frame.admission(ready, 100, 110, now, 20)
    end

    assert {:error, %Error{code: :invalid_native_frame}} =
             Frame.admission(%Ready{clock_ms: 9_223_372_036_854_775_807}, 100, 110, 105, 20)
  end

  test "WOP-X03 request contains only exact integer fields and one LF" do
    assert {:ok, frame} =
             Frame.request(
               18_446_744_073_709_551_615,
               "request-1",
               "read",
               %{},
               60_000,
               9_223_372_036_854_775_807
             )

    assert byte_size(frame) <= 131_072
    assert String.ends_with?(frame, "\n")
    assert {:ok, decoded} = Wotex.JSON.decode(binary_part(frame, 0, byte_size(frame) - 1))

    assert decoded == %{
             "version" => 1,
             "generation" => 18_446_744_073_709_551_615,
             "id" => "request-1",
             "operation" => "read",
             "parameters" => %{},
             "timeout_ms" => 60_000,
             "deadline_ms" => 9_223_372_036_854_775_807
           }
  end

  test "WOP-X03 request rejects malformed and resource-exhausting values before emission" do
    valid = [1, "a", "read", %{}, 1, 1]

    for invalid <- [
          [0, "a", "read", %{}, 1, 1],
          [18_446_744_073_709_551_616, "a", "read", %{}, 1, 1],
          [1, "", "read", %{}, 1, 1],
          [1, "a\n", "read", %{}, 1, 1],
          [1, String.duplicate("a", 65), "read", %{}, 1, 1],
          [1, "a", "eval", %{}, 1, 1],
          [1, "a", "read", [], 1, 1],
          [1, "a", "read", %{}, 0, 1],
          [1, "a", "read", %{}, 60_001, 1],
          [1, "a", "read", %{}, 1, -1],
          [1, "a", "read", %{}, 1, 9_223_372_036_854_775_808],
          [1, "a", "read", %{"payload" => String.duplicate("x", 65_537)}, 1, 1],
          [1, "a", "read", %{"bad" => self()}, 1, 1]
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} = apply(Frame, :request, invalid)
    end

    assert {:ok, _} = apply(Frame, :request, valid)
  end
end
