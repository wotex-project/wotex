defmodule Mix.Tasks.Wotex.SetupTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Setup
  alias Wotex.Workspace.Manifest.Host
  alias Wotex.Workspace.Manifest.Package

  test "takes --no-index only" do
    assert Setup.parse_args([]) == []
    assert Setup.parse_args(~w(--no-index)) == [index: false]
    assert_raise Mix.Error, fn -> Setup.parse_args(~w(--all)) end
  end

  test "fetches the dependencies of a package and then of each of its hosts" do
    host = %Host{path: "hosts/nerves", env: [{"MIX_TARGET", "host"}]}
    package = %Package{name: "lab", app: "lab", hosts: [host]}

    assert Setup.deps_steps(%{package | hosts: []}) == [{"deps.get", ["deps.get"], []}]

    assert Setup.deps_steps(package) == [
             {"deps.get", ["deps.get"], []},
             {"hosts/nerves deps.get", ["deps.get"],
              [cd: "hosts/nerves", env: [{"MIX_TARGET", "host"}]]}
           ]
  end
end
