defmodule WotexLabNerves.SmokeTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Evidence.Record
  alias WotexLabNerves.Smoke

  test "host cohort exercises the target code without claiming hardware boot" do
    assert {:ok,
            %{
              result: %{proposal: 22.0, before_restart: 20.0, after_restart: 21.0},
              evidence: %Record{} = evidence
            }} = Smoke.run()

    assert evidence.scenario_id == "nerves-rpi4-smoke"
    assert Enum.find(evidence.assertions, &(&1.id == "WLB-C10:rpi4-boot")).status == :not_run
    assert Enum.all?(Enum.drop(evidence.assertions, 1), &(&1.status == :pass))
    assert evidence.cleanup == %{status: :ok, details: %{things: 0}}
    refute inspect(evidence) =~ "/" <> "Users/"
  end
end
