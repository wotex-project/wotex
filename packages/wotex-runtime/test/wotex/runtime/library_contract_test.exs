defmodule Wotex.Runtime.LibraryContractTest do
  @moduledoc false

  use ExUnit.Case, async: false

  test "loading the library starts no application callback" do
    assert Application.spec(:wotex_runtime, :mod) in [nil, [], :undefined]
  end

  test "the exact supported operation vocabulary is stable" do
    assert Wotex.Runtime.operations() == [
             :readproperty,
             :writeproperty,
             :observeproperty,
             :unobserveproperty,
             :invokeaction,
             :queryaction,
             :cancelaction,
             :subscribeevent,
             :unsubscribeevent
           ]
  end
end
