# Builds the Hex archive without sibling path dependencies and verifies
# that it ships code, README.md, usage-rules.md, CHANGELOG.md, LICENSE and
# NOTICE only.
# Runs in the full gate: `mix run --no-start bin/check_archive.exs`.

defmodule Wotex.Zigbee.Check.Archive do
  @moduledoc """
  Checks that the distributable Hex archive contains the public library and
  consumer usage rules without repository-only tests, tools or credentials.
  """

  @required ~w(mix.exs README.md usage-rules.md CHANGELOG.md LICENSE NOTICE)
  @forbidden ~w(docs test bin config .check.exs .credo.exs .doctor.exs coveralls.json .agents .claude .codex AGENTS.md CLAUDE.md)

  @spec main() :: :ok
  def main do
    version = Mix.Project.config()[:version]
    suffix = Integer.to_string(System.unique_integer([:positive]))
    temporary = Path.join(System.tmp_dir!(), "wotex_zigbee-archive-" <> suffix)
    File.mkdir_p!(temporary)
    archive = Path.join(temporary, "wotex_zigbee-#{version}.tar")

    result =
      try do
        build!(archive)
        verify!(files(archive, temporary))
        {:ok, sha256(archive)}
      catch
        :throw, {:archive, message} -> {:error, message}
      after
        File.rm_rf!(temporary)
      end

    case result do
      {:ok, digest} ->
        IO.puts("archive sha256: #{digest}")
        IO.puts("archive check passed")
        :ok

      {:error, message} ->
        IO.puts(:stderr, "archive check failed: " <> message)
        System.halt(1)
    end
  end

  defp build!(archive) do
    {output, status} =
      System.cmd("mix", ["hex.build", "--output", archive],
        env: [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}],
        stderr_to_stdout: true
      )

    IO.write(output)
    if status != 0, do: throw({:archive, "mix hex.build exited with #{status}"})
  end

  defp files(archive, temporary) do
    :ok = :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(temporary))
    contents = String.to_charlist(Path.join(temporary, "contents.tar.gz"))
    {:ok, entries} = :erl_tar.table(contents, [:compressed])
    Enum.map(entries, &to_string/1)
  end

  defp verify!(files) do
    missing = Enum.reject(@required, &(&1 in files))
    shipped = Enum.filter(files, &forbidden?/1)
    if missing != [], do: throw({:archive, "archive lacks " <> Enum.join(missing, ", ")})
    if shipped != [], do: throw({:archive, "archive ships " <> Enum.join(shipped, ", ")})
    :ok
  end

  defp forbidden?(file) do
    Enum.any?(@forbidden, &(file == &1 or String.starts_with?(file, &1 <> "/")))
  end

  defp sha256(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end

Wotex.Zigbee.Check.Archive.main()
