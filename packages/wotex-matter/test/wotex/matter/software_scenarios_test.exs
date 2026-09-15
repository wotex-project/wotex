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
        "case \"$PWD\" in */expired_window) exit 1 ;; esac\nprintf 'Server Listening...'; exec sleep 60"
      )

    artifacts = artifacts(executable)
    workspace = Path.join(directory, "fixtures")

    assert_raise Mix.Error, "software_peer_start_failed", fn ->
      SoftwareScenarios.with_fixtures(artifacts, workspace, fn _ -> flunk("setup succeeded") end)
    end

    assert_reaped(workspace, 3)
    assert Path.wildcard(Path.join(workspace, "*-fixture.json")) == []
  end

  test "controller setup starts and reaps only its five preparation peers", %{directory: directory} do
    executable = script(directory, "printf 'Server Listening...'; exec sleep 60")
    host = Path.join(directory, "host")
    File.write!(host, "#!/bin/sh\nexit 1\n")
    File.chmod!(host, 0o500)
    artifacts = Map.put(artifacts(executable), :host, host)
    workspace = Path.join(directory, "fixtures")

    assert_raise Mix.Error, "software_controller_setup_failed", fn ->
      SoftwareScenarios.with_fixtures(artifacts, workspace, fn _ -> flunk("setup succeeded") end)
    end

    assert_reaped(workspace, 5)
    assert length(Path.wildcard(Path.join(workspace, "*"))) == 16
    assert Path.wildcard(Path.join(workspace, "*-fixture.json")) == []
  end

  test "a deferred peer starts inside its case and is reaped on return or callback failure", %{
    directory: directory
  } do
    executable = script(directory, "printf 'Server Listening...'; exec sleep 60")

    for outcome <- [:return, :raise] do
      workspace = Path.join(directory, Atom.to_string(outcome))
      File.mkdir!(workspace)
      File.chmod!(workspace, 0o700)
      pid_file = Path.join(workspace, "peer.pid")

      fixture = %{
        "peer" => %{"executable" => executable, "arguments" => [], "directory" => workspace}
      }

      refute File.exists?(pid_file)

      operation = fn ->
        pid = pid_file |> File.read!() |> String.trim()
        assert {_, 0} = System.cmd("/bin/kill", ["-0", pid], stderr_to_stdout: true)
        if outcome == :raise, do: raise("case failure"), else: :case_completed
      end

      if outcome == :raise do
        assert_raise RuntimeError, "case failure", fn ->
          SoftwareScenarios.with_peer(fixture, operation)
        end
      else
        assert SoftwareScenarios.with_peer(fixture, operation) == :case_completed
      end
    end

    assert_reaped(directory, 2)
  end

  test "an externally supplied fixture retains caller-owned peer setup", %{directory: directory} do
    fixture = %{"controller" => %{}, "node_id" => 1}
    assert SoftwareScenarios.with_peer(fixture, fn -> :external_peer end) == :external_peer
    assert File.ls!(directory) == []
  end

  defp artifacts(executable) do
    Map.new(
      ~w(lighting all_clusters bridge host flow_host resource_host contract_driver controller_test paa untrusted_paa)a,
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
