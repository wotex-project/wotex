defmodule WotexLabWorkbench.SeedsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Mix.Tasks.WotexLab.Seed
  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Seeds, Sessions}

  @moduletag :tmp_dir

  test "Mix generation is repeatable, check-only and allocates no browser state", %{tmp_dir: root} do
    count = Sessions.count()
    Seed.run(["--output", root])
    first = outputs(root)
    Seed.run(["--output", root])
    assert outputs(root) == first
    Seed.run(["--check", "--output", root])
    assert {:ok, things} = Seeds.room(Path.join(root, "room.json"))
    assert Enum.map(things, & &1.key) == ~w(thermostat meter actuator)

    path = Path.join(root, "islands.json")
    File.write!(path, "stale")
    assert_raise Mix.Error, ~r/stale seed data/, fn -> Seed.run(["--check", "--output", root]) end
    assert File.read!(path) == "stale"
    File.rm!(path)
    assert_raise Mix.Error, ~r/stale seed data/, fn -> Seed.run(["--check", "--output", root]) end
    refute File.exists?(path)
    assert Sessions.count() == count
  end

  test "room seeds refuse missing, malformed, oversized and symbolic files", %{tmp_dir: root} do
    assert_invalid(Seeds.room(nil))
    path = Path.join(root, "room.json")
    assert_invalid(Seeds.room(path))
    File.write!(path, "not JSON")
    assert_invalid(Seeds.room(path))
    File.write!(path, String.duplicate(" ", 65_537))
    assert_invalid(Seeds.room(path))
    target = Path.join(root, "target.json")
    File.rename!(path, target)
    File.ln_s!(target, path)
    assert_invalid(Seeds.room(path))
  end

  test "invalid definitions cannot substitute identities, schemes or simulator state" do
    seed =
      :wotex_lab_workbench
      |> Application.app_dir("priv/seeds/room.json")
      |> File.read!()
      |> JSON.decode!()

    [first, second, third] = seed["things"]

    invalid = [
      nil,
      Map.put(seed, "unknown", true),
      %{seed | "things" => [first]},
      %{seed | "things" => [first, first, third]},
      %{seed | "things" => [nil, second, third]},
      %{seed | "things" => [Map.put(first, "key", "arbitrary-role"), second, third]},
      %{seed | "things" => [Map.put(first, "scheme", "https"), second, third]},
      %{seed | "things" => [Map.put(first, "state", %{"temperature" => "warm"}), second, third]},
      %{seed | "things" => [Map.put(first, "state", %{"temperature" => 1.0e12}), second, third]},
      %{seed | "things" => [Map.put(first, "document", %{}), second, third]},
      %{
        seed
        | "things" => [put_in(first, ["document", "id"], second["document"]["id"]), second, third]
      }
    ]

    Enum.each(invalid, &assert_invalid(Seeds.admit_room(&1)))
  end

  test "the checked-in output matches its Elixir seed source" do
    Seed.run(["--check"])
    assert_raise Mix.Error, fn -> Seed.run(["--unknown"]) end
  end

  defp outputs(root),
    do: Map.new(~w(room islands components), &{&1, File.read!(Path.join(root, &1 <> ".json"))})

  defp assert_invalid(result), do: assert({:error, %Error{code: :invalid_seed}} = result)
end
