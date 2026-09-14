defmodule Wotex.CoAP.ContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "package does not register an application callback" do
    assert Application.spec(:wotex_coap, :mod) in [nil, [], :undefined]
  end

  test "structured failures do not imply retries or effects" do
    error = Wotex.CoAP.Error.new(:invalid_value, :address)
    assert error.code == :invalid_value
    assert error.field == :address
    refute error.retryable
    assert error.effect == :none
  end

  test "WCO-C10 the default library gate runs coverage once and all quality checks" do
    {configuration, _} = Code.eval_file(".check.exs")
    tools = configuration[:tools]
    assert configuration[:retry] == false
    assert tools[:ex_unit] == false
    assert tools[:coverage][:command] == "mix coveralls"
    assert tools[:coverage][:env] == %{"MIX_ENV" => "test"}

    for name <- [
          :compiler,
          :formatter,
          :deps_get,
          :unused_deps,
          :mix_audit,
          :hex_audit,
          :credo,
          :doctor,
          :ex_doc,
          :dialyzer,
          :archive,
          :application_free,
          :diff
        ] do
      assert is_binary(tools[name][:command])
    end

    assert tools[:archive][:deps] == [coverage: [status: 0]]
  end
end
