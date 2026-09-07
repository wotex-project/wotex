# Verifies the unpacked Hex archive compiles and defines no application callback.
#
#     mix run --no-start bin/check_archive.exs

defmodule CheckArchive do
  @moduledoc false

  @local_tasks "docs/tasks/local"

  @callback_check """
  Application.load(:wotex_continuum)

  unless Application.spec(:wotex_continuum, :mod) in [nil, [], :undefined] do
    raise "archive defines an application callback"
  end

  IO.puts("archive application callback: none")
  """

  def run do
    root = File.cwd!()
    work = work_directory(root)

    try do
      verify(root, work)
    after
      cleanup(root, work)
    end
  end

  defp verify(root, work) do
    source = Path.join(work, "source")

    run!(work, "mix", ["hex.build", "--unpack", "--output", source],
      cd: root,
      env: [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "dev"}]
    )

    File.ln_s!("../../wotex", Path.join(work, "wotex"))

    if File.exists?(Path.join(source, @local_tasks)) do
      fail(root, work, "archive contains local task state")
    end

    development = [{"WOTEX_PATH_DEPS", "1"}, {"MIX_ENV", "test"}]

    run!(work, "mix", ["deps.get"], cd: source, env: development)
    run!(work, "mix", ["compile", "--warnings-as-errors"], cd: source, env: development)
    run!(work, "mix", ["run", "--no-start", "-e", @callback_check], cd: source, env: development)
  end

  defp run!(work, command, arguments, options) do
    options = Keyword.merge(options, into: IO.stream(), stderr_to_stdout: true)
    {_output, status} = System.cmd(command, arguments, options)

    unless status == 0 do
      root = Path.dirname(work)
      fail(root, work, "#{command} failed with status #{status}")
    end
  end

  defp work_directory(root) do
    suffix = 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    directory = Path.join(root, ".archive-check.#{suffix}")
    File.mkdir_p!(directory)
    directory
  end

  defp cleanup(root, work) do
    if Path.dirname(work) == root and String.starts_with?(Path.basename(work), ".archive-check.") do
      File.rm_rf(work)
    else
      IO.puts(:stderr, "refusing unsafe archive-check cleanup")
      System.halt(1)
    end
  end

  defp fail(root, work, message) do
    cleanup(root, work)
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

CheckArchive.run()
