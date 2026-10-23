defmodule WotexLabWorkbench.DependencySecurityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "the exact reviewed Decimal cohort rejects the advisory payload with default limits" do
    assert Application.spec(:decimal, :vsn) == ~c"3.2.0"

    task =
      Task.async(fn ->
        assert Decimal.Context.get().precision == 34

        for source <- ["1e1000000000", "1e-1000000000"] do
          assert Decimal.parse(source) == :error
          assert_raise Decimal.Error, fn -> Decimal.new(source) end
        end

        assert {Decimal.new("1.25"), ""} == Decimal.parse("1.25")
      end)

    on_exit(fn -> if Process.alive?(task.pid), do: Process.exit(task.pid, :kill) end)
    assert {:ok, _} = Task.yield(task, 1_000)
  end

  test "wrong-typed crypto arguments expose no key material through errors or stack traces" do
    assert Application.spec(:plug_crypto, :vsn) == ~c"2.2.1"
    secret = String.duplicate("secret-canary-", 8)
    salt = "salt-canary-in-security-test"

    for operation <- [:sign, :encrypt, :verify, :decrypt],
        arguments <- [
          [secret, {:invalid, salt}, :payload, []],
          [secret, "salt", :payload, %{secret => salt}]
        ] do
      formatted =
        try do
          apply(Plug.Crypto, operation, arguments)
          flunk("wrong-typed arguments must be refused")
        rescue
          error in ArgumentError -> Exception.format(:error, error, __STACKTRACE__)
        end

      refute formatted =~ secret
      refute formatted =~ salt
    end

    value = %{"scope" => "test"}

    assert {:ok, ^value} =
             Plug.Crypto.verify(secret, "salt", Plug.Crypto.sign(secret, "salt", value))

    assert {:ok, ^value} =
             Plug.Crypto.decrypt(secret, "salt", Plug.Crypto.encrypt(secret, "salt", value))
  end
end
