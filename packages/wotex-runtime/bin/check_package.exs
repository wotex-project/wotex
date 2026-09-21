defmodule Wotex.Runtime.Check.Package do
  @moduledoc false

  @present [
    ".formatter.exs",
    "mix.exs",
    "README.md",
    "usage-rules.md",
    "CHANGELOG.md",
    "LICENSE",
    "NOTICE"
  ]

  @absent [
    ".check.exs",
    ".claude",
    ".elixir_ls",
    ".git",
    ".github",
    "CLAUDE.md",
    "_build",
    "bin",
    "cover",
    "deps",
    "doc",
    "docs",
    "priv/plts",
    "tasks",
    "test"
  ]

  @absent_anywhere ["docs", "tasks"]

  @consumer_test ~S"""
  defmodule RuntimePackageConsumerTest do
    use ExUnit.Case, async: true

    alias Wotex.Runtime.{Context, Error, ExposedThing}

    test "the unpacked archive supports dispatch and typed errors" do
      source_root = System.fetch_env!("WOTEX_RUNTIME_SOURCE_ROOT")
      beam = Wotex.Runtime |> :code.which() |> List.to_string()

      assert String.contains?(beam, "/consumer/_build/")
      refute String.contains?(beam, source_root <> "/")

      assert Application.load(:wotex_runtime) in [:ok, {:error, {:already_loaded, :wotex_runtime}}]
      assert Application.spec(:wotex_runtime, :mod) in [nil, [], :undefined]

      {:ok, td} =
        Wotex.ThingDescription.from_map(%{
          "@context" => Wotex.td_context_1_1(),
          "title" => "Package Consumer",
          "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
          "security" => ["nosec_sc"],
          "properties" => %{
            "temperature" => %{
              "type" => "number",
              "forms" => [%{"href" => "https://example.test/properties/temperature"}]
            }
          }
        })

      context = Context.new!(request_id: "package-consumer")

      {:ok, exposed} =
        ExposedThing.new(td, %{
          {:readproperty, "temperature"} => fn input, received ->
            {:handled, input, received.request_id}
          end
        })

      assert ExposedThing.dispatch(exposed, :readproperty, "temperature", nil, context) ==
               {:handled, nil, "package-consumer"}

      {:ok, without_handler} = ExposedThing.new(td, %{})

      assert {:error, %Error{code: :handler_not_found}} =
               ExposedThing.dispatch(
                 without_handler,
                 :readproperty,
                 "temperature",
                 nil,
                 context
               )
    end
  end
  """

  @spec main() :: :ok
  def main do
    source_root = File.cwd!()
    package_root = Path.join(System.tmp_dir!(), "wotex-runtime-package.#{unique()}")

    result =
      try do
        File.mkdir_p!(package_root)
        verify(source_root, core_archive!(package_root), package_root)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        File.rm_rf!(package_root)
      end

    report(result)
  end

  # The exact core archive is either supplied through WOTEX_CORE_ARCHIVE or, under
  # the sibling switch WOTEX_PATH_DEPS=1, built from the declared wotex path dependency.
  defp core_archive!(package_root) do
    case {System.get_env("WOTEX_CORE_ARCHIVE"), System.get_env("WOTEX_PATH_DEPS")} do
      {nil, "1"} ->
        target = Path.join(package_root, "wotex.tar")
        run!("mix", ["hex.build", "--output", target], core_source!())
        target

      {nil, _switch} ->
        violation("WOTEX_CORE_ARCHIVE must name the exact wotex archive")

      {supplied, _switch} ->
        unless File.regular?(supplied) do
          violation("WOTEX_CORE_ARCHIVE is not a regular file")
        end

        supplied
    end
  end

  defp core_source! do
    case Enum.find(Mix.Project.config()[:deps], &match?({:wotex, _options}, &1)) do
      {:wotex, options} when is_list(options) ->
        Keyword.get(options, :path) || violation("wotex is not declared as a path dependency")

      _other ->
        violation("wotex is not declared as a path dependency")
    end
  end

  defp verify(source_root, core_archive, package_root) do
    runtime_archive = Path.join(package_root, "wotex_runtime-0.1.0.tar")
    unpacked = Path.join(package_root, "runtime")
    core = Path.join(package_root, "core")
    consumer = Path.join(package_root, "consumer")

    run!("mix", ["hex.build", "--output", runtime_archive], source_root)
    unpack!(runtime_archive, unpacked)
    unpack!(core_archive, core)

    Enum.each(@present, &present!(unpacked, &1))
    Enum.each(@absent, &absent!(unpacked, &1))
    Enum.each(@absent_anywhere, &absent_anywhere!(unpacked, &1))

    run!("elixir", [Path.join(source_root, "bin/check_boundary.exs")], unpacked)
    write_consumer!(consumer, unpacked, core)

    environment = [
      {"MIX_ENV", "test"},
      {"WOTEX_RUNTIME_SOURCE_ROOT", source_root}
    ]

    run!("mix", ["deps.get"], consumer, environment)
    run!("mix", ["deps.get", "--check-locked"], consumer, environment)
    run!("mix", ["test", "--warnings-as-errors"], consumer, environment)

    IO.puts("runtime archive sha256: #{digest(runtime_archive)}")
    IO.puts("core archive sha256: #{digest(core_archive)}")
    IO.puts("archive consumer lock sha256: #{digest(Path.join(consumer, "mix.lock"))}")
    IO.puts("archive contents and isolated consumer verified")

    :ok
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp unpack!(archive, destination) do
    outer = destination <> "-outer"
    File.mkdir_p!(outer)
    File.mkdir_p!(destination)
    extract!(archive, outer, [])
    extract!(Path.join(outer, "contents.tar.gz"), destination, [:compressed])
  end

  defp extract!(archive, destination, options) do
    case :erl_tar.extract(
           String.to_charlist(archive),
           options ++ [{:cwd, String.to_charlist(destination)}]
         ) do
      :ok -> :ok
      {:error, reason} -> violation("could not unpack exact archive: #{inspect(reason)}")
    end
  end

  defp write_consumer!(consumer, runtime, core) do
    test_root = Path.join(consumer, "test")
    File.mkdir_p!(test_root)

    File.write!(
      Path.join(consumer, "mix.exs"),
      """
      defmodule RuntimePackageConsumer.MixProject do
        use Mix.Project

        def project do
          [
            app: :runtime_package_consumer,
            version: "0.0.0",
            elixir: "~> 1.18",
            deps: [
              {:wotex, path: #{inspect(core)}, override: true},
              {:wotex_runtime, path: #{inspect(runtime)}}
            ]
          ]
        end

        def application, do: [extra_applications: []]
      end
      """
    )

    File.write!(Path.join(test_root, "package_consumer_test.exs"), @consumer_test)
    File.write!(Path.join(test_root, "test_helper.exs"), "ExUnit.start()\n")
  end

  defp present!(unpacked, entry) do
    unless File.regular?(Path.join(unpacked, entry)) do
      violation("packaged archive is missing #{entry}")
    end
  end

  defp absent!(unpacked, entry) do
    if File.exists?(Path.join(unpacked, entry)) do
      violation("packaged archive contains #{entry}")
    end
  end

  defp absent_anywhere!(unpacked, segment) do
    unpacked
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.map(&Path.relative_to(&1, unpacked))
    |> Enum.filter(&(segment in Path.split(&1)))
    |> case do
      [] -> :ok
      [path | _rest] -> violation("packaged archive contains #{path}")
    end
  end

  defp run!(command, arguments, directory, overrides \\ []) do
    options = [
      cd: directory,
      env: command_environment(overrides),
      into: IO.stream(),
      stderr_to_stdout: true
    ]

    {_output, status} = System.cmd(command, arguments, options)

    unless status == 0 do
      violation("#{command} #{Enum.join(arguments, " ")} failed in #{directory}")
    end
  end

  defp command_environment(overrides) do
    %{
      "ERL_LIBS" => "",
      "MIX_BUILD_PATH" => nil,
      "MIX_DEPS_PATH" => nil,
      "MIX_ENV" => "prod",
      "MIX_PATH" => "",
      "WOTEX_PATH_DEPS" => nil
    }
    |> Map.merge(Map.new(overrides))
    |> Map.to_list()
  end

  defp digest(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp violation(message), do: throw({:violation, message})

  defp report(:ok), do: :ok

  defp report({:violation, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Runtime.Check.Package.main()
