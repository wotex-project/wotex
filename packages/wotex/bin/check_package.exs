defmodule Wotex.Check.Package do
  @moduledoc false

  @present [
    "mix.exs",
    "README.md",
    "LICENSE",
    "NOTICE",
    "CHANGELOG.md",
    "priv/w3c/td-json-schema-validation-1.1.json",
    "priv/w3c/tm-json-schema-validation-1.1.json"
  ]

  @absent [
    ".check.exs",
    ".claude",
    ".elixir_ls",
    ".git",
    ".github",
    "CLAUDE.md",
    "_build",
    "cover",
    "deps",
    "doc",
    "docs",
    "priv/plts",
    "tasks",
    "test"
  ]

  @absent_anywhere ["docs", "tasks"]

  @callback_probe """
  Application.load(:wotex)

  unless Application.spec(:wotex, :mod) in [nil, [], :undefined] do
    raise "archive defines an application callback"
  end

  IO.puts("unpacked archive compiled without an application callback")
  """

  @consumer_test ~S"""
  defmodule WotexArchiveConsumerTest do
    use ExUnit.Case, async: true

    alias Wotex.{
      ActionAffordance,
      DataSchema,
      Error,
      EventAffordance,
      Form,
      PropertyAffordance,
      SecurityScheme,
      ThingDescription,
      ThingModel
    }

    test "the exact archive exposes aggregates, wrappers, helpers, and typed failures" do
      td_json = ~S({"@context":"https://www.w3.org/2022/wot/td/v1.1","title":"Archive Thing","security":["nosec_sc"],"securityDefinitions":{"nosec_sc":{"scheme":"nosec"}}})

      assert {:ok, td} = ThingDescription.parse(td_json)
      assert ThingDescription.to_map(td)["title"] == "Archive Thing"
      assert {:ok, ^td_json} = ThingDescription.encode(td, :source)

      tm_json = ~S({"@context":"https://www.w3.org/2022/wot/td/v1.1","@type":"tm:ThingModel","title":"Archive Model"})

      assert {:ok, tm} = ThingModel.parse(tm_json)
      assert ThingModel.to_map(tm)["title"] == "Archive Model"

      wrappers = [
        {DataSchema, %{"type" => "number"}},
        {Form, %{"href" => "relative"}},
        {PropertyAffordance, %{"forms" => [%{"href" => "relative"}]}},
        {ActionAffordance, %{"forms" => [%{"href" => "relative"}]}},
        {EventAffordance, %{"forms" => [%{"href" => "relative"}]}},
        {SecurityScheme, %{"scheme" => "nosec"}}
      ]

      for {module, input} <- wrappers do
        assert {:ok, value} = apply(module, :new, [input])
        assert apply(module, :to_map, [value]) == input
      end

      assert {:ok, form} = Form.new(%{"href" => "relative"})
      assert Form.href(form) == "relative"
      assert Form.operations(form, for: :property) == ["readproperty", "writeproperty"]

      assert {:ok, property} =
               PropertyAffordance.new(%{"forms" => [%{"href" => "relative"}]})

      assert {:ok, [property_form]} = PropertyAffordance.forms(property)
      assert PropertyAffordance.operations(property, property_form) == [
               "readproperty",
               "writeproperty"
             ]

      assert {:error, %Error{code: :object_required, phase: :value, path: "/"}} =
               ThingDescription.from_map([])

      assert {:error, %Error{code: :invalid_options, phase: :value, path: "/"}} =
               ThingModel.from_map(%{}, :invalid)
    end

    test "the consumer loads Wotex from its isolated build and Wotex has no callback" do
      consumer_root = System.fetch_env!("WOTEX_ARCHIVE_CONSUMER_ROOT")
      source_root = System.fetch_env!("WOTEX_SOURCE_ROOT")
      beam = Wotex |> :code.which() |> List.to_string()
      archive_root = Path.basename(Path.dirname(consumer_root))

      assert String.contains?(beam, "/#{archive_root}/consumer/_build/")
      refute String.contains?(beam, source_root <> "/")

      assert Application.load(:wotex) in [:ok, {:error, {:already_loaded, :wotex}}]
      assert Application.spec(:wotex, :mod) in [nil, [], :undefined]
    end
  end
  """

  @spec main() :: :ok
  def main do
    package_root = Path.join(System.tmp_dir!(), "wotex-package.#{unique()}")
    archive = Path.join(package_root, "wotex-0.1.0.tar")
    unpacked = Path.join(package_root, "unpacked")
    consumer = Path.join(package_root, "consumer")

    result =
      try do
        File.mkdir_p!(package_root)
        verify(archive, unpacked, consumer)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        File.rm_rf!(package_root)
      end

    report(result)
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp verify(archive, unpacked, consumer) do
    source_root = File.cwd!()
    run!("mix", ["hex.build", "--output", archive], source_root)
    unpack!(archive, unpacked)

    Enum.each(@present, &present!(unpacked, &1))
    Enum.each(@absent, &absent!(unpacked, &1))
    Enum.each(@absent_anywhere, &absent_anywhere!(unpacked, &1))

    run!("mix", ["deps.get"], unpacked)
    run!("mix", ["compile", "--warnings-as-errors"], unpacked)
    run!("mix", ["run", "--no-start", "-e", @callback_probe], unpacked)

    write_consumer!(consumer, unpacked)

    consumer_env = [
      {"MIX_ENV", "test"},
      {"WOTEX_ARCHIVE_CONSUMER_ROOT", consumer},
      {"WOTEX_SOURCE_ROOT", source_root}
    ]

    run!("mix", ["deps.get"], consumer, consumer_env)
    run!("mix", ["deps.get", "--check-locked"], consumer, consumer_env)
    run!("mix", ["test", "--warnings-as-errors"], consumer, consumer_env)

    IO.puts("archive sha256: #{digest(archive)}")
    IO.puts("consumer lock sha256: #{digest(Path.join(consumer, "mix.lock"))}")

    IO.puts(
      "TD schema sha256: #{digest(Path.join(unpacked, "priv/w3c/td-json-schema-validation-1.1.json"))}"
    )

    IO.puts(
      "TM schema sha256: #{digest(Path.join(unpacked, "priv/w3c/tm-json-schema-validation-1.1.json"))}"
    )

    IO.puts("independent archive consumer exercised TD, TM, six wrappers, helpers, and errors")

    :ok
  end

  defp unpack!(archive, unpacked) do
    outer = Path.join(Path.dirname(unpacked), "outer")
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

  defp write_consumer!(consumer, unpacked) do
    test_root = Path.join(consumer, "test")
    File.mkdir_p!(test_root)

    File.write!(
      Path.join(consumer, "mix.exs"),
      """
      defmodule WotexArchiveConsumer.MixProject do
        use Mix.Project

        def project do
          [
            app: :wotex_archive_consumer,
            version: "0.0.0",
            elixir: "~> 1.18",
            deps: [{:wotex, path: #{inspect(unpacked)}}]
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
      "WOTEX_PATH_DEPS" => "0"
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

Wotex.Check.Package.main()
