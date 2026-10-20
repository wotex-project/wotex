defmodule Wotex.BLE.Check.WriteModeConsumers do
  @moduledoc false

  @spec run(Path.t(), Path.t()) :: :ok
  def run(archive, temporary) do
    IO.puts("write-mode workspace: " <> temporary)

    archives = [
      {:wotex, build!("wotex", temporary)},
      {:wotex_runtime, build!("wotex-runtime", temporary)},
      {:wotex_ble, archive}
    ]

    for {app, path} <- archives, do: IO.puts("#{app} archive sha256: #{digest(path)}")
    IO.puts("write-mode runner sha256: " <> digest(__ENV__.file))
    elixir = System.find_executable("elixir") || refuse("missing provisioned Elixir")
    erl = System.find_executable("erl") || refuse("missing provisioned Erlang")
    IO.puts("peer interpreter sha256: " <> digest(elixir))
    IO.puts("peer Erlang launcher sha256: " <> digest(erl))

    for family <- ~w(wire runtime) do
      consumer = Path.join(temporary, "write-" <> family)
      File.mkdir_p!(Path.join(consumer, "test"))

      dependencies =
        for {app, path} <- archives do
          directory = Path.join([consumer, "extracted", Atom.to_string(app)])
          unpack!(path, directory)
          {app, [path: directory, env: :prod, override: true]}
        end

      File.write!(Path.join(consumer, "mix.exs"), """
      defmodule WriteArchiveConsumer.MixProject do
        use Mix.Project
        def project, do: [app: :write_archive_consumer, version: "0.0.0",
          elixir: "~> 1.18", deps: #{inspect(dependencies, limit: :infinity)}]
        def application, do: [extra_applications: []]
      end
      """)

      for file <- ["write_identity.exs", "write_runner.exs", "write_#{family}_consumer.exs"] do
        copy!(file, Path.join(consumer, "test/" <> file))
      end

      if family == "wire" do
        copy!("write_peer.exs", Path.join(consumer, "peer.exs"))

        command!(
          "cc",
          [
            "-std=c11",
            "-O2",
            "-Wall",
            "-Wextra",
            "-Werror",
            Path.join(consumer, "extracted/wotex_ble/priv/bluez/native/custody.c"),
            "-o",
            Path.join(consumer, "guardian")
          ],
          consumer,
          []
        )

        IO.puts("archive guardian sha256: " <> digest(Path.join(consumer, "guardian")))
      else
        copy!("write_runtime_client.exs", Path.join(consumer, "test/write_runtime_client.exs"))
      end

      environment = [
        {"WOTEX_PATH_DEPS", nil},
        {"MIX_ENV", "test"},
        {"MIX_BUILD_PATH", nil},
        {"MIX_BUILD_ROOT", nil},
        {"MIX_DEPS_PATH", nil},
        {"MIX_APP_PATH", nil},
        {"ERL_LIBS", nil},
        {"WOTEX_WRITE_FAMILY", family},
        {"WOTEX_WRITE_ELIXIR", elixir},
        {"WOTEX_WRITE_ERL", erl}
      ]

      command!("mix", ["deps.get"], consumer, environment)
      command!("mix", ["compile", "--warnings-as-errors"], consumer, environment)
      IO.puts(family <> " consumer lock sha256: " <> digest(Path.join(consumer, "mix.lock")))
      execute!(consumer, environment, "identity", "baseline", 1, false)
      execute!(consumer, environment, "behavior", "baseline", 5, false)

      for {name, file, from, to} <- mutations(family) do
        source = File.read!(Path.join(consumer, "extracted/wotex_ble/lib/wotex/" <> file))

        unless length(String.split(source, from)) == 2,
          do: refuse("mutation site changed: " <> name)

        replacement = Path.join(consumer, name <> ".ex")
        File.write!(replacement, String.replace(source, from, to, global: false))
        execute!(consumer, environment, "behavior", replacement, 5, true)
      end
    end

    :ok
  end

  defp execute!(consumer, environment, phase, replacement, total, mutant?) do
    {output, status} =
      System.cmd(
        "mix",
        ["run", "--no-start", "--no-compile", "test/write_runner.exs", phase, replacement],
        cd: consumer,
        env: environment,
        stderr_to_stdout: true
      )

    case validate(output, status, total, mutant?) do
      {:ok, counts} ->
        IO.puts(
          Path.basename(consumer) <>
            "/" <> phase <> "/" <> Path.basename(replacement) <> ": " <> JSON.encode!(counts)
        )

      :error ->
        IO.write(output)
        refuse("write consumer or mutation failed")
    end
  end

  @doc false
  @spec validate(String.t(), integer(), pos_integer(), boolean()) :: {:ok, map()} | :error
  def validate(output, status, total, mutant?) do
    with {:ok, result} when is_map(result) <- marker(output, "WRITE_RESULT="),
         {:ok, assertions} when is_map(assertions) <- marker(output, "WRITE_ASSERTIONS="),
         true <- Enum.sort(Map.keys(result)) == ~w(excluded failures skipped total),
         true <- Enum.sort(Map.keys(assertions)) == ~w(assertions errors),
         true <-
           Enum.all?(Map.values(result) ++ Map.values(assertions), &(is_integer(&1) and &1 >= 0)),
         true <-
           result["total"] == total and result["skipped"] == 0 and result["excluded"] == 0 and
             assertions["errors"] == 0,
         true <- expected?(result["failures"], assertions["assertions"], status, total, mutant?) do
      {:ok, Map.merge(result, assertions)}
    else
      _ -> :error
    end
  end

  defp expected?(0, 0, 0, _, false), do: true

  defp expected?(failures, assertions, 1, total, true),
    do: failures in 1..total and assertions >= failures

  defp expected?(_, _, _, _, _), do: false

  defp marker(output, prefix) do
    case Enum.filter(String.split(output, "\n"), &String.starts_with?(&1, prefix)) do
      [line] -> JSON.decode(String.replace_prefix(line, prefix, ""))
      _ -> :error
    end
  end

  defp mutations("wire") do
    [
      {"command_substitution", "ble/procedure.ex", "do: \"write_command\",", "do: \"write\","},
      {"fabricated_acceptance", "ble/bluez/response.ex",
       "defp result(\"write\", nil), do: {:ok, :written}",
       "defp result(\"write\", nil), do: {:ok, :written}\n  defp result(\"write_command\", nil), do: {:ok, %{write_mode: :without_response, evidence: :native_queue_accepted}}"}
    ]
  end

  defp mutations("runtime") do
    [
      {"lost_accepted_status", "ble/transport.ex", "do: :accepted,", "do: :ok,"},
      {"ignored_read_selector", "ble/mapping.ex",
       "defp write_mode_applicability(_, :write), do: :ok",
       "defp write_mode_applicability(_, operation) when operation in [:read, :write], do: :ok"}
    ]
  end

  defp build!(name, temporary) do
    archive = Path.join(temporary, name <> ".tar")

    command!("mix", ["hex.build", "--output", archive], Path.expand("../../" <> name, __DIR__), [
      {"WOTEX_PATH_DEPS", nil},
      {"MIX_ENV", "prod"}
    ])

    archive
  end

  defp unpack!(archive, destination) do
    {:ok, outer} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    {_, contents} = Enum.find(outer, fn {name, _} -> to_string(name) == "contents.tar.gz" end)
    {:ok, files} = :erl_tar.extract({:binary, contents}, [:compressed, :memory])

    for {name, bytes} <- files do
      name = to_string(name)

      if Path.type(name) != :relative or ".." in Path.split(name),
        do: refuse("unsafe archive member")

      path = Path.join(destination, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes)
    end
  end

  defp copy!(name, destination) do
    source = Path.expand("../test/support/archive/" <> name, __DIR__)
    File.cp!(source, destination)
    IO.puts(name <> " source sha256: " <> digest(source))
  end

  defp command!(executable, arguments, directory, environment) do
    {output, status} =
      System.cmd(executable, arguments, cd: directory, env: environment, stderr_to_stdout: true)

    IO.write(output)
    if status != 0, do: refuse("archive consumer command failed")
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp refuse(message), do: throw({:violation, message})
end
