# Builds, inspects, unpacks, compiles, and consumes the exact Wotex Nx archive.
#
#     mix run --no-start bin/check_archive.exs

defmodule WotexNx.CheckArchive do
  @moduledoc false

  @present [
    "mix.exs",
    "README.md",
    "LICENSE",
    "NOTICE",
    "lib/wotex/nx.ex",
    "lib/wotex/nx/encoder.ex",
    "lib/wotex/nx/decoder.ex",
    "docs/specs/WNX.01-observation-numerical-boundary.md"
  ]

  @absent [
    ".check.exs",
    ".claude",
    ".git",
    ".github",
    "CLAUDE.md",
    "_build",
    "bin",
    "cover",
    "deps",
    "doc",
    "docs/tasks",
    "priv",
    "test"
  ]

  @callback_probe """
  for app <- [:wotex, :wotex_nx] do
    Application.load(app)

    unless Application.spec(app, :mod) in [nil, [], :undefined] do
      raise "archive defines an application callback for \#{app}"
    end
  end

  IO.puts("archive application callbacks: none")
  """

  @consumer_test ~S"""
  defmodule WotexNxArchiveConsumerTest do
    use ExUnit.Case, async: true

    alias Wotex.Nx.{Decoder, Encoded, Encoder, Error, Feature, Observation, OutputSchema}
    alias Wotex.Nx.{Row, Schema, Window}

    test "the exact archives execute a bounded observation roundtrip and rejection paths" do
      {:ok, data_schema} = Wotex.DataSchema.new(%{"type" => "number", "unit" => "Cel"})

      {:ok, feature} =
        Feature.new(
          name: "temperature",
          thing_id: "urn:archive:thing",
          affordance_type: :property,
          affordance_name: "temperature",
          data_schema: data_schema
        )

      {:ok, schema} = Schema.new(features: [feature], max_rows: 1)

      {:ok, observation} =
        Observation.new(
          id: "archive-observation",
          thing_id: "urn:archive:thing",
          affordance_type: :property,
          affordance_name: "temperature",
          observed_at: 100,
          value: 21.5,
          unit: "Cel"
        )

      {:ok, window} = Window.new(start: 100, step: 1, count: 1, strategy: :exact)
      assert {:ok, [row]} = Window.resample([observation], schema, window)
      assert {:ok, encoded} = Encoder.encode([row], schema)
      assert Encoded.feature_order(encoded) == ["temperature"]
      assert Encoded.timestamps(encoded) == [100]
      assert Encoded.provenance(encoded) == [%{"temperature" => "archive-observation"}]

      {{value}, {mask}, quality} =
        Nx.Defn.jit_apply(&Function.identity/1, [Encoded.batch(encoded)])

      assert Nx.to_flat_list(value) == [21.5]
      assert Nx.to_flat_list(mask) == [1]
      assert Nx.to_flat_list(quality) == [0]

      {:ok, output_schema} =
        OutputSchema.new(
          kind: :prediction,
          thing_id: "urn:archive:thing",
          affordance_type: :property,
          affordance_name: "temperature",
          data_schema: data_schema
        )

      scalar = Nx.squeeze(value, axes: [0])

      assert {:ok, prediction} =
               Decoder.decode(scalar, output_schema,
                 id: "archive-prediction",
                 produced_at: 101,
                 target_at: 102
               )

      assert prediction.value == 21.5
      assert prediction.thing_id == "urn:archive:thing"

      {:ok, wrong_thing} =
        Observation.new(
          id: "wrong-thing",
          thing_id: "urn:archive:other",
          affordance_type: :property,
          affordance_name: "temperature",
          observed_at: 100,
          value: 21.5,
          unit: "Cel"
        )

      {:ok, wrong_row} = Row.new(100, %{"temperature" => wrong_thing})

      assert {:error, %Error{code: :observation_feature_mismatch}} =
               Encoder.encode([wrong_row], schema)

      assert {:error, %Error{code: :output_shape_mismatch}} =
               Decoder.decode(value, output_schema,
                 id: "invalid-shape",
                 produced_at: 101,
                 target_at: 102
               )
    end

    test "the consumer loads both libraries only from its isolated build" do
      consumer_root = System.fetch_env!("WOTEX_NX_ARCHIVE_CONSUMER_ROOT")

      for {module, source_variable} <- [
            {Wotex.Nx, "WOTEX_NX_SOURCE_ROOT"},
            {Wotex.DataSchema, "WOTEX_CORE_SOURCE_ROOT"}
          ] do
        beam = module |> :code.which() |> List.to_string()
        assert String.contains?(beam, Path.join(consumer_root, "_build"))
        refute String.contains?(beam, System.fetch_env!(source_variable))
      end

      for app <- [:wotex, :wotex_nx] do
        assert Application.load(app) in [:ok, {:error, {:already_loaded, app}}]
        assert Application.spec(app, :mod) in [nil, [], :undefined]
      end
    end
  end
  """

  @spec run() :: :ok
  def run do
    work = work_directory()

    result =
      try do
        verify(File.cwd!(), work)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        cleanup(work)
      end

    report(result)
  end

  defp verify(source_root, work) do
    dependency_source = Mix.Project.deps_paths() |> Map.fetch!(:wotex) |> Path.expand()
    nx_archive = Path.join(work, "wotex_nx-0.1.0.tar")
    core_archive = Path.join(work, "wotex-0.1.0.tar")
    nx_outer = Path.join(work, "nx-outer")
    nx_unpacked = Path.join(work, "wotex_nx")
    core_outer = Path.join(work, "core-outer")
    core_unpacked = Path.join(work, "wotex")
    consumer = Path.join(work, "consumer")

    run!("mix", ["hex.build", "--output", nx_archive], source_root)
    run!("mix", ["hex.build", "--output", core_archive], dependency_source)
    unpack!(nx_archive, nx_outer, nx_unpacked)
    unpack!(core_archive, core_outer, core_unpacked)

    Enum.each(@present, &present!(nx_unpacked, &1))
    Enum.each(@absent, &absent!(nx_unpacked, &1))
    verify_metadata!(Path.join(nx_outer, "metadata.config"))

    development = [{"WOTEX_PATH_DEPS", "1"}, {"MIX_ENV", "test"}]
    run!("mix", ["deps.get"], nx_unpacked, development)
    run!("mix", ["compile", "--warnings-as-errors"], nx_unpacked, development)
    run!("mix", ["run", "--no-start", "-e", @callback_probe], nx_unpacked, development)

    write_consumer!(consumer, nx_unpacked, core_unpacked)

    consumer_environment = [
      {"WOTEX_PATH_DEPS", nil},
      {"MIX_ENV", "test"},
      {"WOTEX_NX_ARCHIVE_CONSUMER_ROOT", consumer},
      {"WOTEX_NX_SOURCE_ROOT", source_root},
      {"WOTEX_CORE_SOURCE_ROOT", dependency_source}
    ]

    run!("mix", ["deps.get"], consumer, consumer_environment)
    run!("mix", ["deps.get", "--check-locked"], consumer, consumer_environment)
    run!("mix", ["test", "--warnings-as-errors"], consumer, consumer_environment)

    IO.puts("wotex_nx archive sha256: #{digest(nx_archive)}")
    IO.puts("wotex archive sha256: #{digest(core_archive)}")
    IO.puts("consumer lock sha256: #{digest(Path.join(consumer, "mix.lock"))}")
    IO.puts("exact archives exercised observation, window, batch, inert output, and rejections")

    :ok
  end

  defp verify_metadata!(path) do
    {:ok, terms} = :file.consult(String.to_charlist(path))
    metadata = Map.new(terms)

    requirements =
      metadata
      |> Map.fetch!(<<"requirements">>)
      |> Map.new(fn fields ->
        requirement = Map.new(fields)
        {Map.fetch!(requirement, <<"name">>), Map.fetch!(requirement, <<"requirement">>)}
      end)

    expected = %{<<"nx">> => <<"~> 0.13.1">>, <<"wotex">> => <<"~> 0.1.0">>}

    unless requirements == expected do
      violation("archive runtime requirements differ from the declared cohort")
    end

    files = Map.fetch!(metadata, <<"files">>)

    if Enum.any?(files, &String.starts_with?(&1, "priv")) do
      violation("archive unexpectedly declares runtime assets")
    end
  end

  defp unpack!(archive, outer, unpacked) do
    File.mkdir_p!(outer)
    File.mkdir_p!(unpacked)
    extract!(archive, outer, [])
    extract!(Path.join(outer, "contents.tar.gz"), unpacked, [:compressed])
  end

  defp extract!(archive, destination, options) do
    archive = String.to_charlist(archive)
    destination = String.to_charlist(destination)

    case :erl_tar.extract(archive, options ++ [{:cwd, destination}]) do
      :ok -> :ok
      {:error, reason} -> violation("could not unpack exact archive: #{inspect(reason)}")
    end
  end

  defp write_consumer!(consumer, nx_unpacked, core_unpacked) do
    test_root = Path.join(consumer, "test")
    File.mkdir_p!(test_root)

    File.write!(
      Path.join(consumer, "mix.exs"),
      """
      defmodule WotexNxArchiveConsumer.MixProject do
        use Mix.Project

        def project do
          [
            app: :wotex_nx_archive_consumer,
            version: "0.0.0",
            elixir: "~> 1.18",
            deps: [
              {:wotex, path: #{inspect(core_unpacked)}, override: true},
              {:wotex_nx, path: #{inspect(nx_unpacked)}}
            ]
          ]
        end

        def application, do: [extra_applications: []]
      end
      """
    )

    File.write!(Path.join(test_root, "archive_consumer_test.exs"), @consumer_test)
    File.write!(Path.join(test_root, "test_helper.exs"), "ExUnit.start()\n")
  end

  defp present!(unpacked, entry) do
    unless File.exists?(Path.join(unpacked, entry)) do
      violation("packaged archive is missing #{entry}")
    end
  end

  defp absent!(unpacked, entry) do
    if File.exists?(Path.join(unpacked, entry)) do
      violation("packaged archive contains #{entry}")
    end
  end

  defp run!(command, arguments, directory, overrides \\ []) do
    environment =
      %{
        "ERL_LIBS" => "",
        "MIX_ENV" => "prod",
        "MIX_PATH" => "",
        "WOTEX_PATH_DEPS" => nil
      }
      |> Map.merge(Map.new(overrides))
      |> Map.to_list()

    {_output, status} =
      System.cmd(command, arguments,
        cd: directory,
        env: environment,
        into: IO.stream(),
        stderr_to_stdout: true
      )

    unless status == 0 do
      violation("#{command} #{Enum.join(arguments, " ")} failed in isolated archive work")
    end
  end

  defp work_directory do
    directory = Path.join(temporary_root(), "wotex-nx-archive.#{unique()}")
    File.mkdir_p!(directory)
    directory
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp cleanup(work) do
    if Path.dirname(work) == temporary_root() and
         String.starts_with?(Path.basename(work), "wotex-nx-archive.") do
      File.rm_rf!(work)
    else
      IO.puts(:stderr, "refusing unsafe archive-check cleanup")
      System.halt(1)
    end
  end

  defp temporary_root, do: System.tmp_dir!() |> Path.expand() |> String.trim_trailing("/")

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

WotexNx.CheckArchive.run()
