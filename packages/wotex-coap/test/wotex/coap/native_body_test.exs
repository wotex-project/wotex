defmodule Wotex.CoAP.NativeBodyTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.CoAP.{Error, Native.Body, Native.Wire}

  @fixture_path Path.expand("../../../docs/specs/fixtures/native-v1.json", __DIR__)
  @fixture Jason.decode!(File.read!(@fixture_path))

  test "WCO-N-F03 releases an exact body only after verified completion" do
    [begin_event, chunk_event, end_event] = fixture("WCO-N-F03")["input"]

    assert {:ok, active} = Body.push(Body.new(), begin_event)
    assert inspect(active) == "#Wotex.CoAP.Native.Body<phase: :active, ...>"

    assert {:ok, partial} = Body.push(active, chunk_event)
    assert inspect(partial) == "#Wotex.CoAP.Native.Body<phase: :active, ...>"
    refute match?({:ok, _, _}, Body.take(partial, "b1"))

    assert {:ok, complete} = Body.push(partial, end_event)
    assert inspect(complete) == "#Wotex.CoAP.Native.Body<phase: :complete, ...>"
    assert {:ok, "ABC", %Body{phase: :idle}} = Body.take(complete, "b1")
  end

  test "WCO-N-F04 poisons and erases state after a wrong offset" do
    [begin_event, wrong_chunk] = fixture("WCO-N-F04")["input"]
    assert {:ok, active} = Body.push(Body.new(), begin_event)
    assert {:error, %Error{code: :native_protocol_error}, failed} = Body.push(active, wrong_chunk)
    assert inspect(failed) == "#Wotex.CoAP.Native.Body<phase: :failed, ...>"

    correct = %{wrong_chunk | "offset" => 0}
    assert_failed(Body.push(failed, correct))
    assert_failed(Body.take(failed, "b1"))
  end

  test "WCO-N-F14 a failed hash cannot authorize a later body response" do
    [begin_event, chunk_event, end_event, response] = fixture("WCO-N-F14")["input"]
    assert {:ok, active} = Body.push(Body.new(), begin_event)
    assert {:ok, partial} = Body.push(active, chunk_event)
    assert_failed(Body.push(partial, end_event))

    assert {:error, %Error{code: :native_protocol_error}} =
             Wire.response(:request, response, "r1", %{})
  end

  test "WCO-N03 assembles the one MiB boundary in ordered 32 KiB chunks" do
    body = :binary.copy(<<0xA5>>, 1_048_576)
    assert {:ok, state} = Body.push(Body.new(), begin_event("maximum", body))

    complete_input =
      0..(byte_size(body) - 1)//32_768
      |> Enum.reduce(state, fn offset, current ->
        chunk = binary_part(body, offset, min(32_768, byte_size(body) - offset))
        assert {:ok, next} = Body.push(current, chunk_event("maximum", offset, chunk))
        next
      end)

    assert {:ok, complete} = Body.push(complete_input, end_event("maximum"))
    assert {:ok, ^body, %Body{phase: :idle}} = Body.take(complete, "maximum")
  end

  test "WCO-N03 preserves an explicit empty body" do
    assert {:ok, active} = Body.push(Body.new(), begin_event("empty", ""))
    assert {:ok, complete} = Body.push(active, end_event("empty"))
    assert {:ok, <<>>, %Body{phase: :idle}} = Body.take(complete, "empty")
  end

  test "WCO-N03 begin events use exact fields, bounds, identifiers and lowercase hashes" do
    baseline = begin_event("b1", "ABC")

    invalid = [
      nil,
      %{},
      Map.put(baseline, "event", "begin"),
      Map.put(baseline, "body_id", ""),
      Map.put(baseline, "body_id", String.duplicate("x", 65)),
      Map.put(baseline, "body_id", "line\nbreak"),
      Map.put(baseline, "body_id", <<255>>),
      Map.put(baseline, "length", -1),
      Map.put(baseline, "length", 1_048_577),
      Map.put(baseline, "length", 3.0),
      Map.put(baseline, "sha256", String.upcase(baseline["sha256"])),
      Map.put(baseline, "sha256", String.duplicate("0", 63)),
      Map.put(baseline, "sha256", String.duplicate("g", 64)),
      Map.put(baseline, "extra", nil)
    ]

    for event <- invalid, do: assert_failed(Body.push(Body.new(), event))

    assert {:ok, active} = Body.push(Body.new(), baseline)
    assert_failed(Body.push(active, baseline))
  end

  test "WCO-N03 chunk events reject gaps, overlap, interleaving and malformed bytes" do
    assert {:ok, active} = Body.push(Body.new(), begin_event("b1", "ABC"))

    invalid = [
      nil,
      %{},
      chunk_event("other", 0, "ABC"),
      chunk_event("b1", 1, "ABC"),
      chunk_event("b1", -1, "ABC"),
      chunk_event("b1", 0, "ABCD"),
      chunk_event("b1", 0, "ABC") |> Map.put("extra", nil),
      %{"event" => "body_chunk", "body_id" => "b1", "offset" => 0, "data" => bytes("ABC")}
      |> put_in(["data", "base64"], "QUJ=")
    ]

    for event <- invalid, do: assert_failed(Body.push(active, event))

    large = :binary.copy(<<0>>, 32_769)
    assert {:ok, large_state} = Body.push(Body.new(), begin_event("large", large))
    assert_failed(Body.push(large_state, chunk_event("large", 0, large)))

    assert {:ok, first} = Body.push(active, chunk_event("b1", 0, "A"))
    assert_failed(Body.push(first, chunk_event("b1", 0, "B")))
    assert {:ok, second} = Body.push(first, chunk_event("b1", 1, "BC"))
    assert {:ok, ^second} = Body.push(second, chunk_event("b1", 3, ""))
  end

  test "WCO-N03 end and take require exact phase, fields, length, hash and identity" do
    assert {:ok, active} = Body.push(Body.new(), begin_event("b1", "ABC"))
    assert_failed(Body.push(active, end_event("b1")))

    assert {:ok, partial} = Body.push(active, chunk_event("b1", 0, "ABC"))

    for event <- [
          end_event("other"),
          Map.put(end_event("b1"), "event", "end"),
          Map.put(end_event("b1"), "extra", nil)
        ] do
      assert_failed(Body.push(partial, event))
    end

    assert {:ok, complete} = Body.push(partial, end_event("b1"))
    assert_failed(Body.take(complete, "other"))
    assert_failed(Body.push(complete, end_event("b1")))
  end

  test "WCO-C02 forged or extended state fails closed without retaining bytes" do
    forged = %Body{
      phase: :active,
      id: "b1",
      length: 3,
      used: 3,
      expected_hash: :crypto.hash(:sha256, "ABC"),
      bytes: "ABD"
    }

    assert_failed(Body.push(forged, end_event("b1")))
    assert_failed(Body.push(Map.put(Body.new(), :extra, "secret-canary"), begin_event("b1", "")))
    assert_failed(Body.push(nil, nil))
    assert_failed(Body.take(nil, "b1"))
  end

  property "WCO-N03 every bounded binary is withheld until its exact digest completes" do
    check all(body <- binary(max_length: 65_536), chunk_size <- integer(1..32_768)) do
      assert {:ok, state} = Body.push(Body.new(), begin_event("property", body))

      partial =
        body
        |> chunks(chunk_size)
        |> Enum.reduce(state, fn {offset, chunk}, current ->
          assert {:ok, next} = Body.push(current, chunk_event("property", offset, chunk))
          next
        end)

      assert {:ok, complete} = Body.push(partial, end_event("property"))
      assert {:ok, ^body, %Body{phase: :idle}} = Body.take(complete, "property")
    end
  end

  defp fixture(id), do: Enum.find(@fixture["cases"], &(&1["id"] == id))

  defp begin_event(id, body) do
    %{
      "event" => "body_begin",
      "body_id" => id,
      "length" => byte_size(body),
      "sha256" => Base.encode16(:crypto.hash(:sha256, body), case: :lower)
    }
  end

  defp chunk_event(id, offset, body) do
    %{"event" => "body_chunk", "body_id" => id, "offset" => offset, "data" => bytes(body)}
  end

  defp end_event(id), do: %{"event" => "body_end", "body_id" => id}
  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}

  defp chunks(<<>>, _), do: []

  defp chunks(body, size) do
    0..(byte_size(body) - 1)//size
    |> Enum.map(fn offset ->
      {offset, binary_part(body, offset, min(size, byte_size(body) - offset))}
    end)
  end

  defp assert_failed(result) do
    assert {:error,
            %Error{
              code: :native_protocol_error,
              class: :protocol,
              effect: :none,
              details: %{}
            }, %Body{phase: :failed} = state} = result

    assert inspect(state) == "#Wotex.CoAP.Native.Body<phase: :failed, ...>"
  end
end
