defmodule Wotex.Nx.LibraryContractTest do
  @moduledoc false

  use ExUnit.Case, async: false

  test "the package has no Application callback or hidden supervision tree" do
    assert Application.spec(:wotex_nx, :mod) in [nil, [], :undefined]
  end

  test "quality codes are stable and complete" do
    assert Wotex.Nx.quality_codes() == %{good: 0, uncertain: 1, bad: 2, missing: 3}
  end
end
