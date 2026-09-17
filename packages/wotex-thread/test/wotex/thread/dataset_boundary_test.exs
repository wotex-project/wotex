defmodule Wotex.Thread.DatasetBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.Thread.{Dataset, Error}

  @corpus Path.expand("../../../priv/fixtures/contract-v1.json", __DIR__)
  @external_resource @corpus
  @corpus_bytes File.read!(@corpus)
  @corpus_sha256 :crypto.hash(:sha256, @corpus_bytes) |> Base.encode16(case: :lower)
  @cases Map.fetch!(Jason.decode!(@corpus_bytes), "cases")

  for fixture <- @cases, fixture["operation"] == "Dataset.decode" do
    @tag requirement: "WTH-S01", scenario: "WTH-V01", corpus_sha256: @corpus_sha256
    test "#{fixture["id"]} WTH-S01 WTH-V01 preserves the exact Dataset observation" do
      fixture = unquote(Macro.escape(fixture))
      input = Base.decode16!(fixture["input"]["bytes_hex"], case: :lower)
      result = Dataset.decode(input)

      assert project(result) == fixture["expectation"]["value"]

      case result do
        {:ok, dataset} -> assert {:ok, ^input} = Dataset.encode(dataset)
        {:error, %Error{effect: :none}} -> :ok
      end
    end
  end

  test "WTH-S01 WTH-V01 rejects forged completeness indexes and malformed public structs" do
    {:ok, complete} = Dataset.decode(active_bytes())
    assert Dataset.complete?(complete, :active)

    for dataset <- [
          %{complete | types: []},
          %{complete | types: :invalid},
          %{complete | entries: []},
          %{complete | entries: [{200, "ok"}], types: [200, 200]},
          %{complete | entries: [{200, "ok"} | :improper], types: [200]},
          %{complete | entries: [{200, :not_bytes}], types: [200]},
          %{complete | entries: [{200, "ok"}], types: [201]},
          %{complete | entries: :invalid},
          nil,
          %{}
        ] do
      assert {:error, %Error{code: :invalid_dataset}} = Dataset.encode(dataset)
      refute Dataset.complete?(dataset, :active)
      refute Dataset.complete?(dataset, :pending)
    end

    for context <- [nil, :unknown, "active", [], %{}] do
      refute Dataset.complete?(complete, context)
    end
  end

  test "WTH-S01 WTH-V01 enforces the complete byte and collection ceilings before serialization" do
    maximum = <<200, 252, 0::size(252 * 8)>>
    assert {:ok, dataset} = Dataset.decode(maximum)
    assert {:ok, ^maximum} = Dataset.encode(dataset)
    assert {:error, %Error{code: :invalid_dataset}} = Dataset.decode(maximum <> <<0>>)

    entries = for type <- 128..254, do: {type, <<>>}
    assert {:ok, bytes} = Dataset.encode(%Dataset{entries: entries, types: Enum.to_list(128..254)})
    assert byte_size(bytes) == 254
    assert {:ok, %Dataset{entries: ^entries}} = Dataset.decode(bytes)

    assert {:error, %Error{code: :invalid_dataset}} =
             Dataset.encode(%Dataset{
               entries: [{255, <<>>} | entries],
               types: [255 | Enum.to_list(128..254)]
             })

    for type <- [-1, 256, :unknown, "200"],
        do:
          assert(
            {:error, %Error{code: :invalid_dataset}} =
              Dataset.encode(%Dataset{entries: [{type, <<>>}], types: [type]})
          )
  end

  test "WTH-S01 WTH-V01 validates known widths, names and duplicate unknown types" do
    widths = %{
      0 => [3],
      1 => [2],
      2 => [8],
      4 => [16],
      5 => [16],
      7 => [8],
      12 => [3, 4],
      14 => [8],
      51 => [8],
      52 => [4]
    }

    for {type, valid_widths} <- widths, size <- 0..17 do
      input = <<type, size>> <> :binary.copy(<<0>>, size)

      if size in valid_widths do
        assert {:ok, _} = Dataset.decode(input)
      else
        assert {:error, %Error{code: :invalid_tlv, details: %{type: ^type}}} = Dataset.decode(input)
      end
    end

    for name <- ["", :binary.copy("a", 17), "a\nb", <<255>>, <<0>>, <<127>>] do
      assert {:error, %Error{code: :invalid_tlv}} = Dataset.decode(<<3, byte_size(name)>> <> name)
    end

    for name <- ["a", :binary.copy("a", 16), "åäö"] do
      assert {:ok, _} = Dataset.decode(<<3, byte_size(name)>> <> name)
    end

    assert {:error, %Error{code: :duplicate_tlv, details: %{type: 200}}} =
             Dataset.decode(<<200, 0, 200, 1, 42>>)
  end

  test "WTH-S01 WTH-V01 presence completeness stays separate from SDK semantic validity" do
    # Deliberately invalid page/channel and zero key values still prove only field presence.
    {:ok, dataset} = Dataset.decode(active_bytes())
    assert Dataset.complete?(dataset, :active)
    refute Dataset.complete?(dataset, :pending)

    {:ok, pending} = Dataset.decode(active_bytes() <> <<51, 8, 0::64, 52, 4, 0::32>>)
    assert Dataset.complete?(pending, :pending)
    refute Dataset.complete?(pending, :active)

    for {type, _} <- dataset.entries do
      entries = Enum.reject(dataset.entries, &(elem(&1, 0) == type))

      refute Dataset.complete?(
               %Dataset{entries: entries, types: Enum.map(entries, &elem(&1, 0))},
               :active
             )
    end

    {:ok, secret} = Dataset.decode(<<5, 16, "dataset-canary!!">>)
    refute inspect(secret) =~ "dataset-canary"
    assert {:error, error} = Dataset.decode(<<5, 15, "dataset-canary!">>)
    refute inspect(error) =~ "dataset-canary"
  end

  property "WTH-S01 WTH-V01 generated unknown tags preserve bytes and order" do
    check all(
            entries <-
              uniq_list_of(tuple({integer(128..255), binary(max_length: 4)}),
                max_length: 20,
                uniq_fun: &elem(&1, 0)
              )
          ) do
      bytes =
        for {type, value} <- entries, into: <<>>, do: <<type, byte_size(value), value::binary>>

      assert {:ok, %Dataset{entries: ^entries} = dataset} = Dataset.decode(bytes)
      assert {:ok, ^bytes} = Dataset.encode(dataset)
      refute Dataset.complete?(dataset, :active)
    end
  end

  defp active_bytes do
    <<0, 3, 255, 255, 255, 1, 2, 0, 0, 2, 8, 0::64, 3, 4, "mesh", 5, 16, 0::128, 7, 8, 0::64, 12, 4,
      0::32, 14, 8, 0::64, 53, 0>>
  end

  defp project({:ok, %Dataset{entries: entries, types: types}}) do
    %{
      "ok" => %{
        "entries" =>
          Enum.map(entries, fn {type, bytes} ->
            [type, %{"bytes_hex" => Base.encode16(bytes, case: :lower)}]
          end),
        "types" => types
      }
    }
  end

  defp project({:error, %Error{code: code, effect: effect}}),
    do: %{"error" => %{"code" => Atom.to_string(code), "effect" => Atom.to_string(effect)}}
end
