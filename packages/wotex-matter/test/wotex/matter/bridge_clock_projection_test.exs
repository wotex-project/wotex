defmodule Wotex.Matter.BridgeClockProjectionTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.Matter.Bridge.ClockProjection
  alias Wotex.Matter.Error

  doctest ClockProjection
  @generation :binary.copy(<<1>>, 16)

  test "explicit rate, generation, quantization and transit preserve one deadline" do
    assert {:ok, projection} = ClockProjection.new(@generation, -1000, -990, 100, {98, 100})
    assert {:ok, -512} = ClockProjection.deadline(projection, @generation, 600, -980)
    assert {:ok, -512} = ClockProjection.deadline(projection, @generation, 600, -513)

    assert {:error, %Error{code: :deadline_exceeded}} =
             ClockProjection.deadline(projection, @generation, 600, -512)

    assert {:error, %Error{code: :deadline_exceeded}} =
             ClockProjection.deadline(projection, @generation, 100, -990)

    assert {:error, %Error{code: :probe_required}} =
             ClockProjection.deadline(projection, @generation, 601, -990)

    assert {:error, %Error{code: :invalid_transport_context}} =
             ClockProjection.deadline(projection, @generation, 600, -991)

    assert {:error, %Error{code: :invalid_transport_context}} =
             ClockProjection.deadline(projection, :binary.copy(<<2>>, 16), 600, -990)
  end

  test "minimum and maximum identities stay exact while malformed and forged values are refused" do
    maximum = 0xFFFFFFFFFFFFFFFF
    assert {:ok, projection} = ClockProjection.new(@generation, 0, 0, maximum - 500, {1, 1})
    assert {:ok, 498} = ClockProjection.deadline(projection, @generation, maximum, 0)

    assert {:error, %Error{code: :invalid_transport_context}} =
             ClockProjection.deadline(projection, @generation, maximum + 1, 0)

    for invalid <- [nil, true, "1", 1.0, -1, maximum + 1] do
      assert {:error, %Error{details: %{}}} =
               ClockProjection.new(@generation, 0, 0, invalid, {1, 1})

      assert {:error, %Error{details: %{}}} =
               ClockProjection.deadline(projection, @generation, invalid, 0)
    end

    for rate <- [
          nil,
          1,
          {0, 1},
          {1, 0},
          {2, 1},
          {1.0, 1},
          {1, 1.0},
          {1, 1_000_001},
          {1_000_001, 1_000_001},
          {1, 1, 1}
        ] do
      assert {:error, %Error{code: :invalid_options, details: %{}}} =
               ClockProjection.new(@generation, 0, 0, 0, rate)

      assert {:error, %Error{code: :invalid_transport_context}} =
               ClockProjection.deadline(%{projection | minimum_rate: rate}, @generation, maximum, 0)
    end

    for generation <- [nil, <<>>, :binary.copy(<<1>>, 15), :binary.copy(<<1>>, 17)],
        do: assert({:error, %Error{}} = ClockProjection.new(generation, 0, 0, 0, {1, 1}))

    for {before_ms, after_ms} <- [
          {nil, 0},
          {0, nil},
          {0.0, 0},
          {1, 0},
          {0, 501},
          {-0x8000000000000001, 0},
          {0, 0x8000000000000000}
        ],
        do:
          assert(
            {:error, %Error{}} = ClockProjection.new(@generation, before_ms, after_ms, 0, {1, 1})
          )

    assert {:ok, maximum_beam} =
             ClockProjection.new(@generation, 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF, 0, {1, 1})

    assert {:error, %Error{code: :deadline_exceeded}} =
             ClockProjection.deadline(maximum_beam, @generation, 500, 0x7FFFFFFFFFFFFFFF)

    assert {:error, %Error{code: :invalid_transport_context}} =
             ClockProjection.deadline(nil, @generation, 500, 0)

    assert {:error, %Error{code: :invalid_transport_context}} =
             ClockProjection.deadline(%{__struct__: ClockProjection}, @generation, 500, 0)

    assert {:error, %Error{code: :invalid_transport_context}} =
             ClockProjection.deadline(projection, @generation, maximum, nil)
  end

  test "independent epochs, qualified rates and both clock quantizations never extend modeled native expiry" do
    for {numerator, denominator} <- [{98, 100}, {1, 1}],
        rate <- 980..1050//10,
        rate * denominator >= numerator * 1000,
        epoch <- [-576_460_752_000, 0, 848_000_000],
        probe_offset <- [0, 1, 99, 499],
        reply_delay <- [0, 1, 50, 499],
        native_fraction <- [0, 1, 500, 999],
        before_fraction <- [0, 17, 999] do
      probe_us = 1_000_000 + probe_offset * 1000 + native_fraction
      beam_us = fn real_us -> epoch * 1000 + div(real_us * rate, 1000) end
      before_ms = -Integer.floor_div(-beam_us.(1_000_000 - before_fraction), 1000)
      after_ms = Integer.floor_div(beam_us.(probe_us + reply_delay * 1000), 1000)
      native_ms = div(probe_us, 1000)
      true_expiry = Integer.floor_div(beam_us.(1_500_000), 1000)

      case ClockProjection.new(
             @generation,
             before_ms,
             after_ms,
             native_ms,
             {numerator, denominator}
           ) do
        {:ok, projection} ->
          case ClockProjection.deadline(projection, @generation, 1500, after_ms) do
            {:ok, deadline} -> assert deadline > after_ms and deadline <= true_expiry
            {:error, %Error{code: :deadline_exceeded}} -> :ok
          end

        {:error, %Error{code: :invalid_options}} ->
          assert after_ms - before_ms > 500 or after_ms < before_ms
      end
    end
  end

  property "arbitrary exchange cells produce a bounded value or a detail-free error" do
    check all(value <- term()) do
      assert {:error, %Error{details: %{}}} = ClockProjection.deadline(value, @generation, 500, 0)

      case ClockProjection.new(@generation, 0, 0, value, {1, 1}) do
        {:ok, projection} ->
          assert is_integer(projection.native_ms) and projection.native_ms in 0..0xFFFFFFFFFFFFFFFF

        {:error, %Error{details: %{}}} ->
          :ok
      end
    end
  end
end
