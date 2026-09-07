defmodule WotexBindingHTTP.Check.Archive do
  @moduledoc false

  @prefix "wotex-binding-http-archive."
  @dependencies ["wotex", "wotex-runtime"]
  @archive_name "wotex_binding_http-0.1.0.tar"

  @metadata [
    ~s({<<"version">>,<<"0.1.0">>}),
    ~s({<<"name">>,<<"wotex">>}),
    ~s({<<"name">>,<<"wotex_runtime">>})
  ]

  @requirement ~s({<<"requirement">>,<<"~> 0.1.0">>})
  @mutable ~r{<<"repository">>,<<"(git|path)"|<<"path">>|WOTEX_PATH_DEPS}
  @machinery ~r{(^|/)(\.claude|AGENTS\.md|CLAUDE\.md|test|deps|_build|\.git)(/|$)}

  @callback_probe """
  Application.load(:wotex_binding_http)
  callback = Application.spec(:wotex_binding_http, :mod)

  unless callback in [nil, [], :undefined] do
    raise "archive defines an application callback"
  end

  IO.puts("archive application callback: none")
  """

  @spec main() :: :ok
  def main do
    root = File.cwd!()
    workspace = Path.dirname(root)
    work = Path.join(System.tmp_dir!(), "#{@prefix}#{unique()}")

    result =
      try do
        verify(root, workspace, work)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        cleanup(work)
      end

    report(result)
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp cleanup(work) do
    if String.starts_with?(work, Path.join(System.tmp_dir!(), @prefix)) do
      File.rm_rf!(work)
    else
      IO.puts(:stderr, "refusing unsafe archive-check cleanup")
      System.halt(1)
    end
  end

  defp verify(root, workspace, work) do
    archive = Path.join(work, @archive_name)
    source = Path.join(work, "source")

    Enum.each(@dependencies, &adjacent!(workspace, &1))

    File.mkdir_p!(work)
    build!(root, ["--output", archive])
    build!(root, ["--unpack", "--output", source])

    metadata = metadata(archive)

    Enum.each(@metadata, &pinned!(metadata, &1))
    requirements!(metadata)
    mutable!(metadata)
    machinery!(archive)

    Enum.each(@dependencies, &File.ln_s!(Path.join(workspace, &1), Path.join(work, &1)))

    compile!(source)

    IO.puts("archive source compiled cleanly: #{digest(archive)}")

    :ok
  end

  defp adjacent!(workspace, dependency) do
    unless File.regular?(Path.join([workspace, dependency, "mix.exs"])) do
      violation("missing adjacent #{dependency} checkout")
    end
  end

  defp build!(root, arguments) do
    environment = [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "dev"}]
    run!("mix", ["hex.build" | arguments], root, environment)
  end

  defp compile!(source) do
    environment = [{"WOTEX_PATH_DEPS", "1"}, {"MIX_ENV", "test"}]

    run!("mix", ["deps.get"], source, environment)
    run!("mix", ["compile", "--warnings-as-errors"], source, environment)
    run!("mix", ["run", "--no-start", "-e", @callback_probe], source, environment)
  end

  defp metadata(archive) do
    {:ok, members} = :erl_tar.extract(String.to_charlist(archive), [:memory])

    case List.keyfind(members, ~c"metadata.config", 0) do
      {_name, content} -> content
      nil -> violation("archive is missing metadata.config")
    end
  end

  defp pinned!(metadata, term) do
    unless String.contains?(metadata, term) do
      violation("archive metadata does not contain #{term}")
    end
  end

  defp requirements!(metadata) do
    count =
      metadata
      |> String.split("\n")
      |> Enum.count(&String.contains?(&1, @requirement))

    if count < 2 do
      violation("archive metadata does not pin both Wotex release requirements")
    end
  end

  defp mutable!(metadata) do
    if Regex.match?(@mutable, metadata) do
      violation("archive metadata contains a mutable dependency source")
    end
  end

  defp machinery!(archive) do
    {:ok, entries} = :erl_tar.table(String.to_charlist(archive))

    if Enum.any?(entries, &Regex.match?(@machinery, List.to_string(&1))) do
      violation("archive contains development or agent machinery")
    end
  end

  defp digest(archive) do
    :sha256
    |> :crypto.hash(File.read!(archive))
    |> Base.encode16(case: :lower)
  end

  defp run!(command, arguments, directory, environment) do
    options = [
      cd: directory,
      env: environment,
      into: IO.stream(),
      stderr_to_stdout: true
    ]

    {_output, status} = System.cmd(command, arguments, options)

    unless status == 0 do
      violation("#{command} #{Enum.join(arguments, " ")} failed")
    end
  end

  defp violation(message), do: throw({:violation, message})

  defp report(:ok), do: :ok

  defp report({:violation, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

WotexBindingHTTP.Check.Archive.main()
