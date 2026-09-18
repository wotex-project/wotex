defmodule Wotex.Lab.SourceCohortTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Test.ChildEnvironment

  @moduletag :integration

  @root Path.expand("../../..", __DIR__)

  test "the everyday check configuration leaves the source guard to explicit refresh" do
    previous = System.get_env("WOTEX_PATH_DEPS")

    on_exit(fn ->
      if previous,
        do: System.put_env("WOTEX_PATH_DEPS", previous),
        else: System.delete_env("WOTEX_PATH_DEPS")
    end)

    for mode <- ["1", nil] do
      if mode,
        do: System.put_env("WOTEX_PATH_DEPS", mode),
        else: System.delete_env("WOTEX_PATH_DEPS")

      {config, []} = Code.eval_file(Path.join(@root, ".check.exs"))
      assert Keyword.fetch!(config, :tools)[:ex_unit] == [command: "mix test"]
      refute Keyword.has_key?(config[:tools], :source_cohort)
    end

    assert File.regular?(Path.join(@root, "bin/check_source_cohort.exs"))
  end

  test "the actual source guard refuses drift missing owners and symlinks without rewriting" do
    workspace =
      Path.join(System.tmp_dir!(), "wotex-cohort-" <> Base.encode16(:crypto.strong_rand_bytes(16)))

    File.mkdir!(workspace)
    File.chmod!(workspace, 0o700)
    on_exit(fn -> File.rm_rf!(workspace) end)
    lab = Path.join(workspace, "wotex-lab")
    File.mkdir_p!(Path.join(lab, "bin"))
    provenance = Path.join(lab, "priv/provenance")
    File.mkdir_p!(provenance)
    script = Path.join(lab, "bin/check_source_cohort.exs")
    File.cp!(Path.join(@root, "bin/check_source_cohort.exs"), script)
    value = "reviewed fixture source\n"

    packages =
      for owner <- ["wotex", "wotex-runtime"] do
        directory = Path.join(workspace, owner)
        File.mkdir_p!(Path.join(directory, "lib"))
        File.write!(Path.join(directory, "lib/value.ex"), value)

        %{
          "package" => String.replace(owner, "-", "_"),
          "repository" => "https://github.com/wotex-project/" <> owner
        }
      end

    File.write!(Path.join(provenance, "source-index.json"), Jason.encode!(%{packages: packages}))
    executable = System.find_executable("elixir")
    assert is_binary(executable)

    assert {json, 0} =
             System.cmd(executable, [script, "--print"],
               env: ChildEnvironment.scrubbed(),
               stderr_to_stdout: true
             )

    cohort = Jason.decode!(json)
    file_digest = Base.encode16(:crypto.hash(:sha256, value), case: :lower)
    tree_digest = :crypto.hash(:sha256, "lib/value.ex\0" <> file_digest <> "\n")
    expected = Base.encode16(tree_digest, case: :lower)
    assert Enum.all?(cohort["packages"], &(&1["files"] == 1 and &1["sha256"] == expected))
    record = Path.join(provenance, "source-cohort.json")
    File.write!(record, json)

    assert {_, 0} =
             System.cmd(executable, [script],
               env: ChildEnvironment.scrubbed(),
               stderr_to_stdout: true
             )

    source = Path.join(workspace, "wotex/lib/value.ex")
    File.write!(source, value <> "changed\n")

    assert {message, 1} =
             System.cmd(executable, [script],
               env: ChildEnvironment.scrubbed(),
               stderr_to_stdout: true
             )

    assert message =~ "workspace source drift"
    assert File.read!(record) == json
    File.write!(source, value)

    owner = Path.join(workspace, "wotex-runtime")
    File.rename!(owner, owner <> ".held")

    assert {message, 1} =
             System.cmd(executable, [script],
               env: ChildEnvironment.scrubbed(),
               stderr_to_stdout: true
             )

    assert message =~ "missing source owner"
    File.rename!(owner <> ".held", owner)

    File.ln_s!(source, Path.join(owner, "lib/link.ex"))

    assert {message, 1} =
             System.cmd(executable, [script],
               env: ChildEnvironment.scrubbed(),
               stderr_to_stdout: true
             )

    assert message =~ "symlink in source cohort"
    assert File.read!(record) == json
  end
end
