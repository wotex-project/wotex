Code.require_file("../../support/software/acceptance.exs", __DIR__)
Code.require_file("../../support/software/command.exs", __DIR__)

defmodule Wotex.Matter.SoftwareAcceptanceTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{SoftwareAcceptance, SoftwareCommand, SoftwareManifest}

  setup do
    {temporary, 0} = System.cmd("pwd", ["-P"], cd: System.tmp_dir!())

    root =
      Path.join(
        String.trim(temporary),
        "wotex-software-acceptance-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "test/support/software"))
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "WMA-C09 the inventory identifies every registered required software case", %{root: root} do
    inventory = SoftwareAcceptance.inventory!("test/support/software/acceptance.json")

    expected =
      inventory["cases"]
      |> Enum.map(&{&1["module"], &1["name"], &1["file"]})
      |> Enum.sort()

    script = """
    ExUnit.start(autorun: false)
    Code.require_file("test/test_helper.exs")
    Path.wildcard("test/**/*_test.exs") |> Enum.each(&Code.require_file/1)
    actual = for {module, _} <- :code.all_loaded(),
      function_exported?(module, :__ex_unit__, 0),
      test <- module.__ex_unit__().tests, test.tags[:software],
      do: [Atom.to_string(module), Atom.to_string(test.name), Path.relative_to(test.tags.file, File.cwd!())]
    IO.puts(Jason.encode!(Enum.sort(actual)))
    """

    log = Path.join(root, "inventory.log")
    result = command(script, log: log)
    assert {:ok, output} = result, File.read!(log)
    assert Jason.decode!(String.trim(output)) == Enum.map(expected, &Tuple.to_list/1)
    assert length(expected) == 36
  end

  test "WMA-B01 required software rejects missing unsafe or invalid fixtures before creating results",
       %{root: root} do
    environment = prepare(root, "passed")
    fixture = environment["WOTEX_TEST_FIXTURE"]
    executable = environment["WOTEX_TEST_EXECUTABLE"]
    link = Path.join(root, "linked.json")
    File.ln_s!(fixture, link)

    for invalid <- [
          Map.delete(environment, "WOTEX_TEST_FIXTURE"),
          %{environment | "WOTEX_REQUIRE_SOFTWARE" => "true"},
          %{environment | "WOTEX_TEST_FIXTURE" => "relative"},
          %{environment | "WOTEX_TEST_FIXTURE" => link},
          %{environment | "WOTEX_TEST_EXECUTABLE" => fixture},
          %{environment | "WOTEX_TEST_FIXTURE" => executable},
          %{environment | "WOTEX_SOFTWARE_RESULT_PATH" => fixture}
        ] do
      assert_raise Mix.Error, fn -> SoftwareAcceptance.configure!(root, invalid) end
      refute File.exists?(environment["WOTEX_SOFTWARE_RESULT_PATH"])
    end

    File.chmod!(fixture, 0o644)
    assert_raise Mix.Error, fn -> SoftwareAcceptance.configure!(root, environment) end
    File.chmod!(fixture, 0o600)

    for value <- [
          "[]",
          "{\"duplicate\":1,\"duplicate\":2}",
          "invalid",
          String.duplicate("x", 131_073)
        ] do
      File.write!(fixture, value)
      assert_raise Mix.Error, fn -> SoftwareAcceptance.configure!(root, environment) end
    end

    refute File.exists?(environment["WOTEX_SOFTWARE_RESULT_PATH"])
  end

  test "WMA-C09 actual ExUnit completion records case identity versions seed and classified evidence",
       %{root: root} do
    environment = prepare(root, "passed")
    assert {:ok, _} = execute(root, environment)
    result = SoftwareManifest.read(environment["WOTEX_SOFTWARE_RESULT_PATH"])
    assert result["status"] == "passed"
    assert result["seed"] == 19
    assert result["elixir"] == System.version()
    assert result["otp"] =~ ~r/\A\d+\.\d+/
    assert result["source_sha256"] == SoftwareManifest.identity(root)["source_sha256"]
    assert result["completed_source_sha256"] == result["source_sha256"]
    assert [%{"status" => "passed", "evidence" => "native-contract"}] = result["cases"]
    assert result["hardware_executed"] == 0

    before = File.read!(environment["WOTEX_SOFTWARE_RESULT_PATH"])
    assert {:error, :command_failed} = execute(root, environment)
    assert File.read!(environment["WOTEX_SOFTWARE_RESULT_PATH"]) == before
  end

  test "WMA-C09 an empty duplicate or escaping case inventory is not acceptance evidence", %{
    root: root
  } do
    environment = prepare(root, "passed")
    path = Path.join(root, "test/support/software/acceptance.json")
    inventory = SoftwareManifest.read(path)
    [item] = inventory["cases"]

    for cases <- [
          [],
          [item, item],
          [%{item | "file" => "test/../probe.exs"}],
          [%{item | "evidence" => "certified"}],
          [Map.put(item, "credential", "secret-canary")],
          [%{item | "file" => "test/missing.exs"}]
        ] do
      SoftwareManifest.write(path, %{inventory | "cases" => cases})
      assert_raise Mix.Error, fn -> SoftwareAcceptance.configure!(root, environment) end
      refute File.exists?(environment["WOTEX_SOFTWARE_RESULT_PATH"])
    end
  end

  test "WMA-C09 skipped filtered missing zero-case failed and hardware runs cannot pass", %{
    root: root
  } do
    for {mode, status} <- [
          {"skipped", "skipped"},
          {"excluded", "excluded"},
          {"missing", "missing"},
          {"zero", "missing"},
          {"failed", "failed"},
          {"invalid", "invalid"},
          {"hardware", "passed"},
          {"unexpected", "passed"},
          {"ordinary_failure", "passed"},
          {"changed_source", "passed"}
        ] do
      directory = Path.join(root, mode)
      File.mkdir_p!(Path.join(directory, "test/support/software"))
      environment = prepare(directory, mode)
      assert {:error, :command_failed} = execute(directory, environment), mode
      path = environment["WOTEX_SOFTWARE_RESULT_PATH"]
      result = SoftwareManifest.read(path)
      assert result["status"] == "failed", mode
      assert [%{"status" => ^status}] = result["cases"]
      refute File.read!(path) =~ "secret-canary"
    end
  end

  defp prepare(root, mode) do
    item = %{
      "file" => "test/probe_test.exs",
      "module" => "Elixir.Wotex.Matter.SoftwareReceiptProbe",
      "name" => "test required case",
      "evidence" => "native-contract"
    }

    inventory = %{
      "schema" => "wotex.matter.software-cases@1",
      "cases" => [item],
      "environment" => %{"WOTEX_TEST_FIXTURE" => "fixture", "WOTEX_TEST_EXECUTABLE" => "executable"}
    }

    SoftwareManifest.write(Path.join(root, "test/support/software/acceptance.json"), inventory)
    fixture = Path.join(root, "fixture.json")
    File.write!(fixture, "{\"credential\":\"secret-canary\"}")
    File.chmod!(fixture, 0o600)
    executable = Path.join(root, "executable")
    File.write!(executable, "fixture executable is never started")
    File.chmod!(executable, 0o700)

    tag =
      case mode do
        "skipped" -> "@tag skip: \"secret-canary\""
        "excluded" -> "@tag :excluded_probe"
        _ -> ""
      end

    setup = if mode == "invalid", do: "setup_all do raise \"secret-canary\" end", else: ""

    body =
      case mode do
        "failed" -> "raise \"secret-canary\""
        "changed_source" -> "File.write!(__ENV__.file, \"changed source\")"
        _ -> "assert true"
      end

    name = if mode == "missing", do: "unregistered case", else: "required case"

    required =
      if mode == "zero",
        do: "",
        else: "#{tag}\n@tag :software\ntest #{inspect(name)} do #{body} end"

    extra =
      case mode do
        "hardware" -> "@tag :hardware\ntest \"hardware case\" do assert true end"
        "unexpected" -> "@tag :software\ntest \"unregistered case\" do assert true end"
        "ordinary_failure" -> "test \"ordinary failure\" do raise \"secret-canary\" end"
        _ -> ""
      end

    File.write!(Path.join(root, item["file"]), """
    defmodule Wotex.Matter.SoftwareReceiptProbe do
      @moduledoc false

      use ExUnit.Case
      #{setup}
      #{required}
      #{extra}
    end
    """)

    %{
      "WOTEX_REQUIRE_SOFTWARE" => "1",
      "WOTEX_SOFTWARE_RESULT_PATH" => Path.join(root, "results.json"),
      "WOTEX_TEST_FIXTURE" => fixture,
      "WOTEX_TEST_EXECUTABLE" => executable
    }
  end

  defp execute(root, environment) do
    script = """
    Code.require_file(#{inspect(Path.expand("test/support/software/acceptance.exs"))})
    ExUnit.start(autorun: false, formatters: [], seed: 19, exclude: [:excluded_probe])
    Wotex.Matter.SoftwareAcceptance.configure!(#{inspect(root)}, #{inspect(environment)})
    Code.require_file(#{inspect(Path.join(root, "test/probe_test.exs"))})
    ExUnit.run()
    """

    log = Path.join(root, "command-#{System.unique_integer([:positive])}.log")
    result = command(script, log: log)

    if result == {:error, :command_failed} and
         not File.exists?(environment["WOTEX_SOFTWARE_RESULT_PATH"]),
       do: flunk(File.read!(log))

    result
  end

  defp command(script, options) do
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    SoftwareCommand.run(
      "elixir",
      paths ++ ["-e", script],
      options ++
        [
          timeout: 15_000,
          env: [{"ERL_FLAGS", "+JMsingle true +S 2:2 +SDcpu 1 +SDio 1"}, {"LANG", "C.UTF-8"}]
        ]
    )
  end
end
