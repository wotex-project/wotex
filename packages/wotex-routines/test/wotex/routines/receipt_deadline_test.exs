Code.require_file("../../support/continuation_fixtures.exs", __DIR__)

defmodule Wotex.Routines.ReceiptDeadlineTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.Test.ContinuationFixtures, as: F

  test "a late staged receipt retains history without hiding an expired step" do
    c =
      F.fixture()
      |> F.compile(%{
        "run_ms" => 20_000,
        "steps" => %{
          "id" => "sequence",
          "kind" => "sequence",
          "steps" => [F.effect("first"), F.effect("second")]
        }
      })

    {:ok, first} = F.advance(c)

    admission =
      Map.merge(c.event, %{
        "kind" => "admission",
        "path" => [0],
        "ref" => "charge:1",
        "outcome" => "held"
      })

    {:ok, held} = F.advance(%{c | event: admission}, first["run"])
    handoff = Map.merge(c.event, %{"kind" => "handoff", "path" => [0], "ref" => "handoff:1"})
    {:ok, sent} = F.advance(%{c | event: handoff}, held["run"])
    basis = hd(c.context["bases"])

    report =
      Map.merge(c.event, %{
        "kind" => "result",
        "path" => [0],
        "ref" => "report:1",
        "stage" => "reported_match",
        "outcome" => "accepted",
        "report_contract" => basis["evidence"]["report_contract"]
      })

    late = %{c | event: report, time: %{c.time | "elapsed_ms" => 15_020}}
    assert {:ok, result} = F.advance(late, sent["run"])
    assert result["outcome"] == "expired"
    assert result["run"]["reason"] == "deadline_elapsed"
    assert result["proposals"] == []
    assert result["run"]["spent"] == sent["run"]["spent"]
    record = Enum.find(result["run"]["steps"], &(&1["path"] == [0]))
    assert record["receipts"]["reported_match"]["ref"] == "report:1"

    timely = %{late | time: %{c.time | "elapsed_ms" => 15_019}}
    assert {:ok, result} = F.advance(timely, sent["run"])
    assert result["outcome"] == "running"
    assert [%{"path" => [1]}] = result["proposals"]
  end

  test "a late held admission remains charged when expiry stops continuation" do
    c = F.fixture() |> F.compile(%{"run_ms" => 20_000})
    {:ok, first} = F.advance(c)

    admission =
      Map.merge(c.event, %{
        "kind" => "admission",
        "path" => [],
        "ref" => "charge:1",
        "outcome" => "held"
      })

    late = %{c | event: admission, time: %{c.time | "elapsed_ms" => 15_020}}
    assert {:ok, result} = F.advance(late, first["run"])
    assert result["outcome"] == "expired"
    assert result["proposals"] == []
    assert [%{"ref" => "charge:1"}] = result["run"]["spent"]
    assert hd(result["run"]["steps"])["receipts"]["admission"]["outcome"] == "held"
  end
end
