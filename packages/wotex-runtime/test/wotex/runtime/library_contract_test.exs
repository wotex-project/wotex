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
             :unsubscribeevent,
             :readallproperties,
             :writeallproperties,
             :readmultipleproperties,
             :writemultipleproperties,
             :observeallproperties,
             :unobserveallproperties,
             :queryallactions,
             :subscribeallevents,
             :unsubscribeallevents
           ]

    assert Wotex.Runtime.thing_operations() == [
             :readallproperties,
             :writeallproperties,
             :readmultipleproperties,
             :writemultipleproperties,
             :observeallproperties,
             :unobserveallproperties,
             :queryallactions,
             :subscribeallevents,
             :unsubscribeallevents
           ]

    assert Wotex.Runtime.interaction_type(:readproperty) == :property
    assert Wotex.Runtime.interaction_type(:invokeaction) == :action
    assert Wotex.Runtime.interaction_type(:subscribeevent) == :event
    assert Wotex.Runtime.interaction_type(:readallproperties) == :thing
    assert Wotex.Runtime.interaction_type(:invented) == nil
  end
end
