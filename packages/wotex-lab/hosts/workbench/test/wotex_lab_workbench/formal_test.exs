defmodule WotexLabWorkbench.FormalTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Formal

  test "the optional profile exposes a closed catalogue and explicit unsupported state" do
    assert map_size(Formal.properties()) > 0
    assert :safe in Formal.variants()

    {property, _description} = Enum.at(Formal.properties(), 0)

    assert {:ok, ^property, :safe} =
             Formal.admit(Atom.to_string(property), "safe")

    assert {:error, %Error{code: :unknown_selection}} = Formal.admit("caller", "safe")
    assert {:error, %Error{code: :unknown_selection}} = Formal.admit(property, :safe)
    assert {:error, :unsupported} = Formal.profile()
    assert {:error, :unsupported} = Formal.verify(property, :safe)

    assert {:error, %Error{code: :unknown_selection}} =
             Formal.verify(:caller_property, :caller_variant)
  end
end
