defmodule CompositionArchiveIdentityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "public dependencies load only from this extracted cohort and remain passive" do
    root = File.cwd!()
    supplied = System.fetch_env!("WOTEX_ROUTINES_CONSUMER_ROOT")

    assert Map.take(File.stat!(root), [:inode, :major_device]) ==
             Map.take(File.stat!(supplied), [:inode, :major_device])

    for module <- [
          Wotex.Routines.Compiler,
          Wotex.Routines.Kernel,
          Wotex.Routines.Collection,
          Wotex.Routines.Arbitration,
          Wotex.Routines.Time,
          Wotex.Routines.Event,
          Wotex.Routines.Run,
          Wotex.Routines.Witness,
          Wotex.JSON,
          WotexContinuum
        ] do
      Code.ensure_loaded!(module)

      assert module
             |> :code.which()
             |> List.to_string()
             |> String.starts_with?(Path.join(root, "_build"))
    end

    for app <- [:wotex, :wotex_continuum, :wotex_routines] do
      assert Application.spec(app, :mod) in [nil, []]
    end
  end
end
