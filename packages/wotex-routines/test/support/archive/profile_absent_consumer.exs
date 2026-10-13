defmodule ProfileAbsentConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.{Basis, Error, Input, InputMapping}

  test "ordinary routine values work while the explicitly optional profile producer refuses" do
    v = Jason.decode!(File.read!("input.json"))
    refute Code.ensure_loaded?(Wotex.Profiles.Proposal)
    assert {:ok, _} = Basis.new(v["basis"], v["registry"], v["limits"])

    assert {:error, %Error{code: :missing_producer}} =
             InputMapping.new(v["mapping"], v["registry"], v["limits"])

    context = %{
      "registry" => v["registry"],
      "limits" => v["limits"],
      "reader_limits" => v["reader_limits"]
    }

    assert {:error, %Error{code: :missing_producer}} =
             Input.project(v["proposal"], v["mapping"], v["metadata"], context)
  end
end
