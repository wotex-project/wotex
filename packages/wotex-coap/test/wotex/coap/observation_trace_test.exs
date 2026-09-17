defmodule Wotex.CoAP.ObservationTraceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @corpus Path.expand("../../../priv/fixtures/contract-v1.json", __DIR__)

  @tag fixture_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(@corpus)), case: :lower)
  test "WCO-D05 WCO-S01 WCO-S03 WCO-F-OBSERVE-CANCEL-RACE exact virtual execution trace" do
    corpus =
      @corpus
      |> File.read!()
      |> Jason.decode!()

    fixture = Enum.find(corpus["cases"], &(&1["id"] == "WCO-F-OBSERVE-CANCEL-RACE"))
    assert fixture["operation"] == "observation.trace"

    for _ <- 1..20 do
      observed = Wotex.CoAP.TestObservationTrace.run(fixture["input"])
      assert observed == fixture["expectation"]["value"]
    end
  end
end
