defmodule Wotex.Profiles.ProposalTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Compiler, Error, Interpreter, Proposal}
  alias Wotex.Profiles.Test.Fixtures, as: F

  defp proposal do
    closure = %{
      "definitions" => [F.definition()],
      "bindings" => [F.json("installed-binding")],
      "contracts" => F.json("installed-contracts")
    }

    {:ok, projection} =
      Compiler.compile(F.json("compiler-profile"), closure, F.json("capture"), F.limits())

    report = %{
      "channel_id" => "sample",
      "profile_sha256" => projection.data["profile_sha256"],
      "binding" => projection.data["binding"],
      "capture_epoch" => projection.data["capture_epoch"],
      "source_ref" => "source",
      "source_epoch" => String.duplicate("e", 32),
      "sequence" => "9",
      "source_time" => nil,
      "receipt_time" => %{"epoch" => String.duplicate("f", 32), "monotonic_us" => "-1000"},
      "continuity" => "retained",
      "quality" => "usable",
      "quality_reason" => nil,
      "value" => %{"type" => "sint", "value" => "25"}
    }

    {:ok, value} = Interpreter.project(projection, report, F.limits())
    value
  end

  test "map and exact native round trips preserve all provenance" do
    data = proposal()
    assert {:ok, native} = Proposal.new(data, F.limits())
    assert {:ok, ^data} = Proposal.to_map(native, F.limits())
    assert {:ok, ^data} = Proposal.to_map(data, F.limits())
    assert data["receipt_time"]["monotonic_us"] == "-1000"
    assert Proposal.identity()["id"] == "urn:wotex:profiles:proposal"
    {:ok, bytes} = Wotex.JSON.encode(F.json("../contracts/proposal"))

    digest =
      Base.encode16(:crypto.hash(:sha256, "wotex.profile.proposal-contract@1\n" <> bytes),
        case: :lower
      )

    assert Proposal.identity()["sha256"] == digest
  end

  test "malformed, forged and inconsistent values refuse without retaining payloads" do
    data = proposal()

    for bad <- [
          Map.put(data, "private-canary", "secret-canary"),
          Map.delete(data, "semantic"),
          Map.put(data, "affordance", %{"kind" => "thing", "name" => "x"}),
          put_in(data, ["affordance", "name"], "secret-canary/route"),
          Map.put(data, "normalized_value", 1),
          Map.put(data, "unit", %{}),
          Map.put(data, "capture_digest", "bad"),
          Map.put(data, "closure_sha256", "bad"),
          Map.put(data, "compiler_ref", %{}),
          Map.put(data, "semantic", %{}),
          Map.put(data, "interpretation", "qualified"),
          Map.put(data, "quality", "stale"),
          Map.put(data, "normalized_value", %{"type" => "null"}),
          Map.put(data, "source_epoch", "bad"),
          Map.put(%Proposal{data: data}, :extra, "secret-canary"),
          %URI{}
        ] do
      assert {:error, %Error{code: :invalid_input} = error} = Proposal.new(bad, F.limits())
      refute inspect(error) =~ "canary"
      refute error.path =~ "/report"
    end
  end

  test "nonusable observations remain null and unconverted" do
    for quality <- ~w(unknown invalid stale) do
      data =
        proposal()
        |> Map.merge(%{
          "quality" => quality,
          "normalized_value" => %{"type" => "null"},
          "interpretation" => "unconverted",
          "unit" => nil
        })

      assert {:ok, %Proposal{data: ^data}} = Proposal.new(data, F.limits())

      assert {:error, %Error{code: :invalid_input}} =
               Proposal.new(Map.put(data, "interpretation", "profile_declared"), F.limits())
    end
  end

  test "selected budgets and source clock bounds are enforced" do
    data = proposal()

    assert {:error, %Error{code: :input_limit}} =
             Proposal.new(data, Map.put(F.limits(), "max_bytes", 128))

    assert {:error, %Error{code: :invalid_input, path: "/limits"}} = Proposal.new(data, %{})

    time = %{
      "utc" => "2026-10-14T12:00:00.123456Z",
      "trust" => "trusted",
      "uncertainty_us" => "1001"
    }

    assert {:ok, _} = Proposal.new(Map.put(data, "source_time", time), F.limits())

    for bad <- [
          Map.put(time, "uncertainty_us", nil),
          Map.put(time, "utc", "2026-10-14T12:00:00+01:00")
        ] do
      assert {:error, %Error{code: :invalid_input}} =
               Proposal.new(Map.put(data, "source_time", bad), F.limits())
    end
  end
end
