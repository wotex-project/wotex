defmodule Wotex.Lab.ErrorTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error

  test "errors are structured values that can also be raised" do
    error =
      Error.new(:invalid_options, :construction, "options rejected", path: "/a", class: :permanent)

    assert %Error{code: :invalid_options, phase: :construction, path: "/a", class: :permanent} =
             error

    assert error.details == %{}
    assert Exception.message(error) == "options rejected"

    assert_raise Error, "options rejected", fn -> raise error end

    raised =
      assert_raise Error, fn ->
        raise Error, code: :unavailable, phase: :adapter, message: "peer unavailable"
      end

    assert raised.code == :unavailable
    assert raised.phase == :adapter
    assert raised.path == nil
    assert raised.class == nil
  end
end
