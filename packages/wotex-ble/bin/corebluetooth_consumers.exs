defmodule Wotex.BLE.Check.CoreBluetoothConsumers do
  @moduledoc false

  @spec run(Path.t(), Path.t()) :: :ok
  def run(archive, temporary) do
    unless :os.type() == {:unix, :darwin},
      do: refuse("CoreBluetooth archive consumers require macOS")

    IO.puts("CoreBluetooth workspace: " <> temporary)

    archives = [
      {:wotex, build!("wotex", temporary)},
      {:wotex_runtime, build!("wotex-runtime", temporary)},
      {:wotex_ble, archive}
    ]

    for {app, path} <- archives, do: IO.puts("#{app} archive sha256: #{digest(path)}")
    IO.puts("CoreBluetooth runner sha256: " <> digest(__ENV__.file))

    {lock, _} =
      Path.expand("../mix.lock", __DIR__)
      |> File.read!()
      |> Code.string_to_quoted!(emit_warnings: false)
      |> Code.eval_quoted()

    seed =
      inspect(Map.take(lock, [:decimal, :ex_json_schema, :jason, :telemetry]),
        pretty: true,
        limit: :infinity
      ) <> "\n"

    for family <- ~w(client runtime) do
      consumer = Path.join(temporary, "core-" <> family)
      File.mkdir_p!(Path.join(consumer, "test"))

      dependencies =
        for {app, path} <- archives do
          directory = Path.join([consumer, "extracted", Atom.to_string(app)])
          unpack!(path, directory)
          {app, [path: directory, env: :prod, override: true]}
        end

      File.write!(Path.join(consumer, "mix.exs"), """
      defmodule CoreArchiveConsumer.MixProject do
        use Mix.Project
        def project, do: [app: :core_archive_consumer, version: "0.0.0", consolidate_protocols: false,
          elixir: "~> 1.18", deps: #{inspect(dependencies, limit: :infinity)}]
        def application, do: [extra_applications: []]
      end
      """)

      File.write!(Path.join(consumer, "mix.lock"), seed)

      for file <-
            ~w(corebluetooth_identity.exs corebluetooth_build.exs corebluetooth_runner.exs corebluetooth_support.exs) ++
              ["corebluetooth_#{family}_consumer.exs"] do
        copy!(file, Path.join(consumer, "test/" <> file))
      end

      copy!("corebluetooth_peer.cpp", Path.join(consumer, "peer.cpp"))

      environment = [
        {"WOTEX_PATH_DEPS", nil},
        {"MIX_ENV", "test"},
        {"HEX_OFFLINE", "1"},
        {"MIX_BUILD_PATH", nil},
        {"MIX_BUILD_ROOT", nil},
        {"MIX_DEPS_PATH", nil},
        {"MIX_APP_PATH", nil},
        {"ERL_LIBS", nil},
        {"WOTEX_CORE_FAMILY", family}
      ]

      command!("mix", ["deps.get"], consumer, environment)
      command!("mix", ["compile", "--warnings-as-errors"], consumer, environment)

      command!(
        "xcrun",
        [
          "clang++",
          "-std=c++17",
          "-O1",
          "-Wall",
          "-Wextra",
          "-Werror",
          "-I.",
          "peer.cpp",
          "-o",
          "peer"
        ],
        consumer,
        environment
      )

      IO.puts(family <> " lock sha256: " <> digest(Path.join(consumer, "mix.lock")))
      IO.puts(family <> " independent peer sha256: " <> digest(Path.join(consumer, "peer")))
      execute!(consumer, environment, "identity", "baseline", 1, false)
      execute!(consumer, environment, "build", "baseline", 1, false)
      execute!(consumer, environment, "behavior", "baseline", 7, false)

      for {name, file, from, to} <- mutations(family) do
        source = File.read!(Path.join(consumer, "extracted/wotex_ble/lib/wotex/" <> file))

        unless length(String.split(source, from)) == 2,
          do: refuse("mutation site changed: " <> name)

        replacement = Path.join(consumer, name <> ".ex")
        File.write!(replacement, String.replace(source, from, to, global: false))
        execute!(consumer, environment, "behavior", replacement, 7, true)
      end
    end

    :ok
  end

  defp execute!(consumer, environment, phase, replacement, total, mutant?) do
    {output, status} =
      System.cmd(
        "mix",
        ["run", "--no-start", "--no-compile", "test/corebluetooth_runner.exs", phase, replacement],
        cd: consumer,
        env: environment,
        stderr_to_stdout: true
      )

    case validate(output, status, total, mutant?) do
      {:ok, counts} ->
        for line <- String.split(output, "\n"),
            String.starts_with?(line, "CORE_BUILD="),
            do: IO.puts(line)

        IO.puts(
          Path.basename(consumer) <>
            "/" <> phase <> "/" <> Path.basename(replacement) <> ": " <> JSON.encode!(counts)
        )

      :error ->
        IO.write(output)
        refuse("CoreBluetooth consumer or mutation failed")
    end
  end

  @doc false
  @spec validate(String.t(), integer(), pos_integer(), boolean()) :: {:ok, map()} | :error
  def validate(output, status, total, mutant?) do
    with {:ok, result} when is_map(result) <- marker(output, "CORE_RESULT="),
         {:ok, assertions} when is_map(assertions) <- marker(output, "CORE_ASSERTIONS="),
         true <- Enum.sort(Map.keys(result)) == ~w(excluded failures skipped total),
         true <- Enum.sort(Map.keys(assertions)) == ~w(assertions errors),
         true <-
           Enum.all?(Map.values(result) ++ Map.values(assertions), &(is_integer(&1) and &1 >= 0)),
         true <-
           result["total"] == total and result["skipped"] == 0 and result["excluded"] == 0 and
             assertions["errors"] == 0,
         true <- expected?(result["failures"], assertions["assertions"], status, total, mutant?),
         true <- not String.contains?(output, "warning:") do
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

  defp mutations("client") do
    [
      {"command_substitution", "ble/core_bluetooth/connection.ex",
       "defp kind(%{type: :write, write_mode: :without_response}), do: :write_command",
       "defp kind(%{type: :write, write_mode: :without_response}), do: :write"},
      {"fabricated_queue_evidence", "ble/core_bluetooth/response.ex",
       "  def result(:write, nil, _), do: {:ok, :written}",
       "  def result(:write, nil, _), do: {:ok, :written}\n  def result(:write_command, nil, _), do: {:ok, %{write_mode: :without_response, evidence: :native_queue_accepted}}"},
      {"premature_credit", "ble/core_bluetooth/connection.ex",
       "        message = {:ble_stream, id, receipt, event}",
       "        state = acknowledge(state, %{\"version\" => 1, \"generation\" => state.handle.generation, \"stream_version\" => 1, \"event\" => \"notification_ack\", \"subscription_id\" => id, \"sequence\" => elem(receipt, 0)})\n        message = {:ble_stream, id, receipt, event}"}
    ]
  end

  defp mutations("runtime") do
    [
      {"lost_accepted_status", "ble/transport.ex", "do: :accepted,", "do: :ok,"},
      {"ignored_target", "ble/transport.ex",
       "true <- Keyword.get(config, :target) == mapping.target,", "true <- true,"},
      {"foreign_backend", "ble/runtime_frame.ex",
       "with true <- Map.get(mapping, :backend) == CoreBluetooth,",
       "with true <- Map.get(mapping, :backend) in [CoreBluetooth, Wotex.BLE.BlueZ],"}
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

    if status != 0 do
      IO.write(output)

      refuse(
        "CoreBluetooth archive command failed: " <> executable <> " " <> Enum.join(arguments, " ")
      )
    end

    IO.puts(
      Path.basename(directory) <>
        ": " <> executable <> " " <> Enum.join(arguments, " ") <> " passed"
    )
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp refuse(message), do: throw({:violation, message})
end
