Code.require_file("test/support/software/scenarios.exs")

defmodule Wotex.Matter.SoftwareScenariosTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.SoftwareScenarios

  setup do
    directory =
      Path.join(System.tmp_dir!(), "wotex-scenarios-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "partial peer startup failure reaps every earlier owned peer", %{directory: directory} do
    executable =
      script(
        directory,
        "case \"$PWD\" in */lighting) exit 1 ;; esac\nprintf 'Server Listening...'; exec sleep 60"
      )

    artifacts = artifacts(executable)
    workspace = Path.join(directory, "fixtures")

    assert_raise Mix.Error, "software_peer_start_failed", fn ->
      SoftwareScenarios.with_fixtures(artifacts, workspace, fn _ -> flunk("setup succeeded") end)
    end

    assert_reaped(workspace, 3)
    assert Path.wildcard(Path.join(workspace, "*-fixture.json")) == []
  end

  test "controller setup failure reaps all thirteen ready peers", %{directory: directory} do
    executable = script(directory, "printf 'Server Listening...'; exec sleep 60")
    host = Path.join(directory, "host")
    File.write!(host, "#!/bin/sh\nexit 1\n")
    File.chmod!(host, 0o500)
    artifacts = Map.put(artifacts(executable), :host, host)
    workspace = Path.join(directory, "fixtures")

    assert_raise Mix.Error, "software_controller_setup_failed", fn ->
      SoftwareScenarios.with_fixtures(artifacts, workspace, fn _ -> flunk("setup succeeded") end)
    end

    assert_reaped(workspace, 13)
    assert Path.wildcard(Path.join(workspace, "*-fixture.json")) == []
  end

  defp artifacts(executable) do
    Map.new(
      ~w(lighting all_clusters bridge host flow_host contract_driver controller_test paa untrusted_paa)a,
      &{&1, executable}
    )
  end

  defp script(directory, body) do
    path = Path.join(directory, "peer")
    File.write!(path, "#!/bin/sh\nprintf '%s' \"$$\" > peer.pid\n" <> body <> "\n")
    File.chmod!(path, 0o500)
    path
  end

  defp assert_reaped(workspace, count) do
    files = Path.wildcard(Path.join(workspace, "*/peer.pid"))
    assert length(files) == count

    for path <- files do
      pid = path |> File.read!() |> String.trim()
      assert {_, status} = System.cmd("/bin/kill", ["-0", pid], stderr_to_stdout: true)
      assert status != 0
      assert Bitwise.band(File.stat!(Path.dirname(path)).mode, 0o777) == 0o700
    end
  end
end
