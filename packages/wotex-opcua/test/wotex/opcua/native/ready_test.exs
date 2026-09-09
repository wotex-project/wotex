defmodule Wotex.OPCUA.Native.ReadyTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Error
  alias Wotex.OPCUA.Native.Ready
  doctest Ready

  @cases Jason.decode!(File.read!("docs/specs/fixtures/native-ready-v1.json"))["cases"]

  for fixture <- @cases do
    @fixture fixture
    test "#{fixture["id"]} exact readiness bytes match the pure fixture" do
      frame = Base.decode64!(@fixture["frame_base64"])

      case @fixture["expected"] do
        %{"clock_ms" => clock} ->
          assert Ready.decode(frame) == {:ok, %Ready{clock_ms: clock}}

        %{"error" => "invalid_native_ready"} ->
          assert {:error, %Error{code: :invalid_native_ready, field: :ready, details: %{}}} =
                   Ready.decode(frame)
      end
    end
  end

  test "WOP-X01 malformed non-binary readiness is a structured failure" do
    for value <- [nil, false, 42, [], %{}, {:ready, 42}, self()] do
      assert {:error, %Error{code: :invalid_native_ready}} = Ready.decode(value)
    end
  end
end
