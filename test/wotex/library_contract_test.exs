defmodule Wotex.LibraryContractTest do
  @moduledoc false

  use ExUnit.Case, async: false

  test "the library has no application callback" do
    assert Application.spec(:wotex, :mod) in [nil, [], :undefined]
  end

  test "the public media type and context are exact" do
    assert Wotex.td_media_type() == "application/td+json"
    assert Wotex.td_context_1_1() == "https://www.w3.org/2022/wot/td/v1.1"
  end
end
