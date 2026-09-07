defmodule Wotex.Lab.LibraryContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Plugin

  test "Lab application owns no startup callback or registered process" do
    assert Application.spec(:wotex_lab, :mod) in [nil, [], :undefined]
    assert Application.spec(:wotex_lab, :registered) == []
    assert Application.spec(:wotex_lab, :vsn) == ~c"0.1.0"
  end

  test "plugin contract exposes explicit composition without discovery" do
    assert Enum.sort(Plugin.behaviour_info(:callbacks)) ==
             [capabilities: 0, child_specs: 1, id: 0, manifest: 0]
  end
end
