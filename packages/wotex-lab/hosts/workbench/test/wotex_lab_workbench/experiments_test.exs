defmodule WotexLabWorkbench.ExperimentsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Experiments

  test "the host and experiment catalogue expose only the three admitted runs" do
    assert WotexLabWorkbench.version() == "0.1.0"
    assert WotexLabWorkbench.lab() == WotexLabWorkbench.Lab
    assert Enum.map(Experiments.all(), & &1.id) == ~w(thermal window_anomaly smart_room)

    for experiment <- Experiments.all() do
      assert {:ok, ^experiment} = Experiments.fetch(experiment.id)
      assert {:ok, values} = Experiments.admit(experiment, %{})
      assert length(values) == length(experiment.parameters)

      assert Experiments.defaults(experiment) |> Map.keys() |> Enum.sort() ==
               experiment.parameters |> Enum.map(& &1.name) |> Enum.sort()
    end

    assert {:error, %Error{code: :unknown_experiment}} = Experiments.fetch("unknown")
    assert {:error, %Error{code: :unknown_experiment}} = Experiments.fetch(:unknown)
  end

  test "parameters are typed and bounded without creating caller atoms" do
    {:ok, window} = Experiments.fetch("window_anomaly")

    assert {:ok, values} =
             Experiments.admit(window, %{
               "seed" => "42",
               "count" => "64",
               "window_count" => "16",
               "threshold" => "2.25",
               "fill" => "-4.5",
               "backend" => "binary"
             })

    assert values[:seed] == 42
    assert values[:count] == 64
    assert values[:threshold] == 2.25
    assert values[:backend] == Nx.BinaryBackend

    for params <- [
          %{"seed" => "0"},
          %{"count" => "513"},
          %{"threshold" => "nan"},
          %{"backend" => "caller-module"},
          %{"seed" => String.duplicate("1", 33)}
        ] do
      assert {:error, %Error{code: :invalid_parameter}} = Experiments.admit(window, params)
    end

    assert {:error, %Error{code: :invalid_parameters}} = Experiments.admit(window, [])

    prefix = "unknown_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    for suffix <- 1..100 do
      caller_name = "#{prefix}_#{suffix}"
      assert_raise ArgumentError, fn -> String.to_existing_atom(caller_name) end
      assert {:error, %Error{code: :unknown_experiment}} = Experiments.fetch(caller_name)

      for experiment <- Experiments.all(),
          parameter <- experiment.parameters,
          parameter.type == :select do
        assert {:error, %Error{code: :invalid_parameter}} =
                 Experiments.admit(experiment, %{parameter.name => caller_name})
      end

      # Other async tests and lazy module loading may add unrelated VM atoms.
      # The contract is that these exact caller-supplied names never become atoms.
      assert_raise ArgumentError, fn -> String.to_existing_atom(caller_name) end
    end
  end
end
