# Inspects an unpacked Hex candidate and proves production requirements use Hex.
# Runs through Mix: `mix run --no-start bin/check_package.exs`.

Code.require_file("support/work_directory.exs", __DIR__)

defmodule Wotex.Lab.Check.Package do
  @moduledoc false

  @required ~w(lib/wotex/lab.ex mix.exs README.md LICENSE NOTICE
               docs/specs/catalogue.yaml docs/plans/wotex-lab-completion.md priv/models/manifest.json
               docs/provenance/source-index.json priv/fixtures/thermal/thing-description.json
               priv/conformance/native/Cargo.toml priv/conformance/native/Cargo.lock
               priv/conformance/native/src/main.rs priv/conformance/native/src/config.rs
               priv/conformance/native/src/accounting.rs
               priv/fixtures/thermal/manifest.json priv/fixtures/thermal/expected-output.json
               priv/cookbooks/thermal-nx.livemd priv/cookbooks/smart-room.livemd)
  @excluded ~r{\A(?:docs/tasks|deps|_build|test|bin|\.git)(?:/|\z)}

  def run do
    root = Path.expand("..", __DIR__)
    File.cd!(root)
    work = Wotex.Lab.Check.WorkDirectory.create!(root, :package)
    source = Path.join(work, "source")

    env = [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}]

    {output, status} =
      System.cmd("mix", ["hex.build", "--unpack", "--output", source],
        env: env,
        stderr_to_stdout: true
      )

    status == 0 || abort("hex.build failed:\n" <> output)

    Enum.each(@required, &(File.regular?(Path.join(source, &1)) || abort("archive missing #{&1}")))

    files =
      source
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)

    Enum.each(files, fn file ->
      relative = Path.relative_to(file, source)
      Regex.match?(@excluded, relative) && abort("excluded archive content: #{relative}")

      if String.starts_with?(relative, "priv/conformance/") and
           relative not in ~w(priv/conformance/native/Cargo.toml
                             priv/conformance/native/Cargo.lock
                             priv/conformance/native/src/main.rs
                             priv/conformance/native/src/config.rs
                             priv/conformance/native/src/accounting.rs
                             priv/conformance/native/probes/main.rs
                             priv/conformance/native/tests/lifecycle.rs) do
        abort("unexpected containment artifact (source-only profile): #{relative}")
      end

      match?({:ok, %File.Stat{type: :symlink}}, File.lstat(file)) &&
        abort("symlink in archive: #{relative}")
    end)

    IO.puts("package contents: #{length(files)} files; no independent-consumer claim")

    metadata_check = ~S'''
    deps = Mix.Project.config()[:deps]
    Enum.each(deps, fn dep ->
      opts = dep |> Tuple.to_list() |> List.last()
      if is_list(opts) and Enum.any?([:path, :git, :github], &Keyword.has_key?(opts, &1)) do
        raise "production dependency is not an artifact requirement"
      end

      if is_list(opts) and Keyword.has_key?(opts, :system_env) do
        raise "production dependency carries a build environment"
      end
    end)
    IO.puts("package metadata: production requirements use Hex")
    '''

    {output, status} =
      System.cmd(
        "mix",
        ["run", "--no-compile", "--no-deps-check", "--no-start", "-e", metadata_check],
        env: [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}],
        stderr_to_stdout: true
      )

    IO.write(output)
    status == 0 || abort("production metadata check failed")
    IO.puts("inspected candidate retained at #{source}")
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.Package.run()
