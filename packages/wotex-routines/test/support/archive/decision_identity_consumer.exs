defmodule DecisionArchiveIdentityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "public query uses only extracted modules without application startup" do
    root = File.cwd!()
    supplied = System.fetch_env!("WOTEX_ROUTINES_CONSUMER_ROOT")

    assert Map.take(File.stat!(root), [:inode, :major_device]) ==
             Map.take(File.stat!(supplied), [:inode, :major_device])

    for module <- [
          Wotex.Routines.Compiler,
          Wotex.Routines.Kernel,
          Wotex.Routines.Collection,
          Wotex.Routines.Arbitration,
          Wotex.Routines.Basis,
          Wotex.Routines.Transition,
          Wotex.Routines.Decision,
          Wotex.Routines.Time,
          Wotex.Routines.Event,
          Wotex.Routines.Run,
          Wotex.Routines.Edge,
          Wotex.Routines.Limits,
          Wotex.Routines.Profile,
          Wotex.Routines.Model,
          Wotex.JSON,
          WotexContinuum
        ] do
      Code.ensure_loaded!(module)

      assert String.starts_with?(
               List.to_string(:code.which(module)),
               Path.join(root, "_build") <> "/"
             )
    end

    running = Enum.map(Application.started_applications(), &elem(&1, 0))

    for app <- [:wotex, :wotex_continuum, :wotex_routines] do
      assert Application.load(app) in [:ok, {:error, {:already_loaded, app}}]
      assert Application.spec(app, :mod) in [nil, []]
      refute app in running
    end

    base = DecisionArchiveInputs.base()
    c = DecisionArchiveInputs.compile(base, "passive:query")
    input = DecisionArchiveInputs.input(base, [c])
    collection = DecisionArchiveInputs.collection(base, input)
    assert :ok == Wotex.Routines.Decision.verify_point(input, collection, base.profile, base.limits)
  end
end
