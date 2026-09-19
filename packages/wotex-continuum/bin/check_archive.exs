# Builds one exact Hex archive and exercises it through isolated consumers.
#
#     WOTEX_PATH_DEPS=1 mix run --no-start bin/check_archive.exs

defmodule WotexContinuum.CheckArchive do
  @moduledoc false

  @package_version "0.1.0"
  @core_package_version "0.1.0"
  @jason_floor "1.4.5"
  @released_packages [:decimal, :ex_json_schema, :jason]

  @present [
    "mix.exs",
    "README.md",
    "LICENSE",
    "NOTICE",
    "CHANGELOG.md",
    "priv/schemas/wct-01.schema.json",
    "priv/schemas/wct-02.schema.json",
    "priv/schemas/wct-03.schema.json",
    "priv/vectors/canonical/wct-01-manifest.json",
    "priv/vectors/canonical/wct-02-observation.json",
    "priv/vectors/canonical/wct-03-lifecycle.json"
  ]

  @absent [
    ".check.exs",
    ".claude",
    ".elixir_ls",
    ".git",
    ".github",
    "AGENTS.md",
    "CLAUDE.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "GOVERNANCE.md",
    "SECURITY.md",
    "_build",
    "bin",
    "cover",
    "coveralls.json",
    "deps",
    "doc",
    "docs",
    "priv/plts",
    "provenance",
    "specs",
    "test"
  ]

  # Markdown documentation reaches consumers through HexDocs; no `docs/` tree
  # and no task-tracker path may travel inside the archive.
  @forbidden_segments ["docs", "tasks"]

  @contract_consumer_test ~S"""
  defmodule WotexContinuumArchiveContractTest do
    use ExUnit.Case, async: true

    alias Wotex.ThingDescription

    alias WotexContinuum.{
      ActionIntent,
      ActionResult,
      Capability,
      Codec,
      Manifest,
      ObservationProposal,
      ThingReference
    }

    test "declared compatibility is evaluated from the archive" do
      capability_input = %{
        id: "local-buffering",
        version: "1.2.0",
        operations: ["enqueue", "drain"],
        modes: [:connected_onprem],
        network: :local,
        degradation: :queue,
        extensions: %{"https://example.org/capability/profile" => "bounded"}
      }

      assert {:ok, capability} = Capability.new(capability_input)

      assert {:ok, manifest} =
               Manifest.new(%{
                 manifest_id: "manifest-archive-1",
                 artifact: %{
                   name: "archive-worker",
                   version: "1.0.0",
                   digest:
                     "sha256:1111111111111111111111111111111111111111111111111111111111111111"
                 },
                 compatibility: %{
                   schema_requirement: "~> 2.0",
                   required_capabilities: [
                     %{id: "local-buffering", version_requirement: "~> 1.0"}
                   ]
                 },
                 supported_modes: [:connected_onprem],
                 capabilities: [capability_input],
                 extensions: %{"https://example.org/manifest/priority" => "normal"}
               })

      assert :ok = Manifest.compatible_with?(manifest, "2.0.0", [capability])

      assert {:error, [%{type: :missing_capability, id: "local-buffering"}]} =
               Manifest.compatible_with?(manifest, "2.0.0", [])

      assert_round_trip(manifest)
    end

    test "supplied TD references and WCT.02 round trips need no host service" do
      assert {:ok, thing_description} = ThingDescription.from_map(valid_td())
      assert {:ok, observation} = ObservationProposal.new(observation_input())
      assert {:ok, intent} = ActionIntent.new(intent_input())

      assert :ok = ThingReference.validate(observation, thing_description)
      assert :ok = ThingReference.validate(intent, thing_description)

      assert_round_trip(observation)
      assert_round_trip(intent)

      assert {:ok, result} =
               ActionResult.new(%{
                 result_id: "result-archive-1",
                 intent_id: intent.intent_id,
                 status: :succeeded,
                 output: %{"accepted_level" => 42},
                 started_at: "2026-09-02T10:00:03Z",
                 completed_at: "2026-09-02T10:00:04Z",
                 context: scope("2026-09-02T10:00:04Z"),
                 extensions: %{"https://example.org/result/source" => "archive"}
               })

      assert_round_trip(result)
    end

    test "the dependency graph and BEAMs come only from the isolated consumer" do
      assert_hex_installation!()
      assert Application.load(:wotex_continuum) in [
               :ok,
               {:error, {:already_loaded, :wotex_continuum}}
             ]

      assert Application.spec(:wotex_continuum, :mod) in [nil, [], :undefined]
      assert to_string(Application.spec(:jason, :vsn)) ==
               System.fetch_env!("WOTEX_EXPECTED_JASON_VERSION")
    end

    defp assert_round_trip(value) do
      assert {:ok, encoded} = Codec.encode(value, canonical: true)
      assert {:ok, decoded} = Codec.decode(encoded)
      assert decoded == value
    end

    defp assert_hex_installation! do
      lock = Mix.Dep.Lock.read()

      for package <- ~w(decimal ex_json_schema jason wotex wotex_continuum)a do
        assert {:hex, _, _, _, _, _, "hexpm", _} = Map.fetch!(lock, package)
      end

      consumer_root = System.fetch_env!("WOTEX_ARCHIVE_CONSUMER_ROOT")
      source_root = System.fetch_env!("WOTEX_CONTINUUM_SOURCE_ROOT")
      core_root = System.fetch_env!("WOTEX_CORE_SOURCE_ROOT")

      for module <- [Wotex, WotexContinuum] do
        beam = module |> :code.which() |> List.to_string()
        assert String.starts_with?(beam, Path.join(consumer_root, "_build"))
        refute String.contains?(beam, source_root)
        refute String.contains?(beam, core_root)
      end

      assert to_string(Application.spec(:jason, :vsn)) ==
               System.fetch_env!("WOTEX_EXPECTED_JASON_VERSION")
    end

    defp valid_td do
      %{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:thing:pump-7",
        "title" => "Archive Pump",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "actions" => %{
          "setLevel" => %{
            "input" => %{"type" => "object"},
            "forms" => [
              %{
                "href" => "https://example.test/pumps/7/actions/setLevel",
                "op" => "invokeaction"
              }
            ]
          }
        }
      }
    end

    defp observation_input do
      %{
        proposal_id: "proposal-archive-1",
        thing_id: "urn:example:thing:pump-7",
        affordance_type: :property,
        affordance_name: "level",
        value: %{"value" => 42.5, "unit" => "percent"},
        observed_at: "2026-09-02T10:00:01Z",
        sequence: 8,
        quality: %{"status" => "measured"},
        context: scope("2026-09-02T10:00:01Z"),
        extensions: %{"https://example.org/observation/source" => "archive"}
      }
    end

    defp intent_input do
      %{
        intent_id: "intent-archive-1",
        thing_id: "urn:example:thing:pump-7",
        action_name: "setLevel",
        input: %{"level" => 42},
        requested_at: "2026-09-02T10:00:02Z",
        idempotency_key: "set-level-archive-1",
        context: scope("2026-09-02T10:00:02Z"),
        extensions: %{"https://example.org/intent/source" => "archive"}
      }
    end

    defp scope(observed_at) do
      %{
        execution_id: "exec-archive-1",
        node_id: "edge-archive-a",
        mode: %{deployment: :connected_onprem, connectivity: :connected},
        observed_at: observed_at,
        extensions: %{"https://example.org/scope/cohort" => "candidate"}
      }
    end
  end
  """

  @reference_consumer_test ~S"""
  defmodule WotexContinuumArchiveReferenceTest do
    use ExUnit.Case, async: true

    alias Wotex.ThingDescription

    alias WotexContinuum.{
      ActionResult,
      Capability,
      Codec,
      Compatibility,
      Error,
      Lifecycle,
      ThingReference
    }

    test "every packaged vector executes from the exact dependency extraction" do
      vector_root = Path.join(dependency_root(), "priv/vectors")

      valid = Path.wildcard(Path.join([vector_root, "valid", "*.json"]))
      canonical = Path.wildcard(Path.join([vector_root, "canonical", "*.json"]))
      invalid = Path.wildcard(Path.join([vector_root, "invalid", "*.json"]))
      compatibility = Path.wildcard(Path.join([vector_root, "compatibility", "*.json"]))

      assert length(valid) == 13
      assert length(canonical) == 13
      assert length(invalid) >= 19
      assert length(compatibility) == 2

      for path <- valid do
        source = File.read!(path)
        assert {:ok, value} = Codec.decode(source), path
        assert {:ok, first} = Codec.encode(value, canonical: true), path
        assert {:ok, recovered} = Codec.decode(first), path
        assert {:ok, second} = Codec.encode(recovered, canonical: true), path
        assert first == second, path
      end

      for path <- canonical do
        vector = path |> File.read!() |> Jason.decode!()
        assert {:ok, value} = WotexContinuum.from_map(vector["input"]), path
        assert {:ok, encoded} = Codec.encode(value, canonical: true), path
        assert encoded == vector["canonical"], path
      end

      for path <- invalid do
        vector = path |> File.read!() |> Jason.decode!()
        assert {:error, %Error{} = error} = Codec.decode(Jason.encode!(vector["input"])), path
        assert Atom.to_string(error.code) == vector["expected"]["code"], path
        assert Atom.to_string(error.phase) == vector["expected"]["phase"], path
        assert error.path == vector["expected"]["path"], path
      end

      for path <- compatibility do
        vector = path |> File.read!() |> Jason.decode!()
        assert {:ok, requirements} = Compatibility.new(vector["requirements"]), path

        capabilities =
          Enum.map(vector["capabilities"], fn input ->
            assert {:ok, capability} = Capability.new(input), path
            capability
          end)

        result =
          Compatibility.evaluate(
            requirements,
            vector["actual_schema_version"],
            capabilities
          )

        case vector["expected"] do
          "compatible" -> assert result == :ok, path
          expected -> assert Enum.map(elem(result, 1), &Atom.to_string(&1.type)) == expected, path
        end
      end
    end

    test "failure, unknown effects, extensions, and lifecycle recovery stay data-only" do
      context = scope("2026-09-02T10:00:04Z")
      action_vector =
        dependency_root()
        |> Path.join("priv/vectors/valid/wct-02-action-intent.json")
        |> File.read!()

      assert {:ok, intent} = Codec.decode(action_vector)
      assert {:ok, thing_description} = ThingDescription.from_map(valid_td(intent.thing_id))
      assert :ok = ThingReference.validate(intent, thing_description)

      assert {:ok, failed} =
               ActionResult.new(%{
                 result_id: "result-archive-failed",
                 intent_id: "intent-archive-failed",
                 status: :failed,
                 error: %{
                   code: "provider_error",
                   message: "consumer-observed failure",
                   details: %{"retryable" => false}
                 },
                 completed_at: "2026-09-02T10:00:04Z",
                 context: context,
                 extensions: %{"https://example.org/result/trace" => "failed"}
               })

      assert_round_trip(failed)

      assert {:ok, unknown} =
               ActionResult.new(%{
                 result_id: "result-archive-unknown",
                 intent_id: "intent-archive-unknown",
                 status: :unknown,
                 context: context,
                 extensions: %{"https://example.org/result/trace" => "unreconciled"}
               })

      assert_round_trip(unknown)
      assert unknown.status == :unknown
      assert unknown.output_present? == false

      assert {:ok, staged} =
               Lifecycle.new(%{
                 subject_id: "worker-archive-1",
                 state: :staged,
                 generation: 9,
                 changed_at: "2026-09-02T10:00:00Z",
                 extensions: %{"https://example.org/lifecycle/cohort" => "candidate"}
               })

      assert {:ok, ready} =
               Lifecycle.transition(staged, :ready, staged.changed_at, reason: "validated")

      assert ready.generation == 10
      assert ready.extensions == staged.extensions
      assert ready.changed_at == staged.changed_at
      assert_round_trip(ready)

      assert {:error, %Error{code: :invalid_transition, path: "/state"}} =
               Lifecycle.transition(ready, :degraded, ready.changed_at)
    end

    test "the second dependency graph and BEAMs are independently isolated" do
      lock = Mix.Dep.Lock.read()

      for package <- ~w(decimal ex_json_schema jason wotex wotex_continuum)a do
        assert {:hex, _, _, _, _, _, "hexpm", _} = Map.fetch!(lock, package)
      end

      consumer_root = System.fetch_env!("WOTEX_ARCHIVE_CONSUMER_ROOT")
      source_root = System.fetch_env!("WOTEX_CONTINUUM_SOURCE_ROOT")
      core_root = System.fetch_env!("WOTEX_CORE_SOURCE_ROOT")

      for module <- [Wotex, WotexContinuum] do
        beam = module |> :code.which() |> List.to_string()
        assert String.starts_with?(beam, Path.join(consumer_root, "_build"))
        refute String.contains?(beam, source_root)
        refute String.contains?(beam, core_root)
      end
    end

    defp assert_round_trip(value) do
      assert {:ok, encoded} = Codec.encode(value, canonical: true)
      assert {:ok, decoded} = Codec.decode(encoded)
      assert decoded == value
    end

    defp dependency_root do
      Mix.Project.deps_paths()
      |> Map.fetch!(:wotex_continuum)
      |> Path.expand()
    end

    defp scope(observed_at) do
      %{
        execution_id: "exec-archive-reference",
        node_id: "edge-archive-reference",
        mode: %{deployment: :air_gapped, connectivity: :disconnected},
        observed_at: observed_at
      }
    end

    defp valid_td(thing_id) do
      %{
        "@context" => Wotex.td_context_1_1(),
        "id" => thing_id,
        "title" => "Reference Consumer Thing",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"]
      }
    end
  end
  """

  @spec run() :: :ok
  def run do
    source_root = File.cwd!()
    core_root = core_source_root!()
    work = work_directory()

    result =
      try do
        verify(source_root, core_root, work)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        cleanup(work)
      end

    report(result)
  end

  defp verify(source_root, core_root, work) do
    repository = Path.join(work, "repository")
    tarballs = Path.join(repository, "tarballs")
    unpacked = Path.join(work, "unpacked")
    private_key = Path.join(work, "registry-private.pem")
    outer = Path.join(work, "outer")

    continuum_archive =
      Path.join(tarballs, "wotex_continuum-#{@package_version}.tar")

    core_archive = Path.join(tarballs, "wotex-#{@package_version}.tar")

    File.mkdir_p!(tarballs)

    build_archive!(source_root, continuum_archive)
    build_archive!(core_root, core_archive)
    fetch_released_packages!(source_root, tarballs)
    unpack!(continuum_archive, unpacked)
    verify_archive_metadata!(outer)
    verify_archive_contents!(unpacked, source_root, core_root)
    write_private_key!(private_key)
    build_registry!(source_root, repository, private_key)

    with_registry(repository, work, fn repository_url ->
      consumers = [
        {"contract-consumer", @contract_consumer_test, [], locked_version!(source_root, :jason)},
        {"reference-consumer", @reference_consumer_test, [], locked_version!(source_root, :jason)},
        {"floor-consumer", @contract_consumer_test,
         [{:jason, "== #{@jason_floor}", [override: true]}], @jason_floor}
      ]

      Enum.map(consumers, fn {name, test_source, dependencies, expected_jason} ->
        consumer = Path.join(work, name)
        write_consumer!(consumer, test_source, dependencies)

        lock_digest =
          exercise_consumer!(
            consumer,
            repository_url,
            Path.join(repository, "public_key"),
            continuum_archive,
            source_root,
            core_root,
            expected_jason
          )

        {name, lock_digest}
      end)
    end)
    |> then(&print_evidence(source_root, core_root, unpacked, continuum_archive, core_archive, &1))

    :ok
  end

  defp core_source_root! do
    case Map.fetch(Mix.Project.deps_paths(), :wotex) do
      {:ok, path} -> Path.expand(path)
      :error -> violation("the development core dependency is not resolved")
    end
  end

  defp build_archive!(directory, archive) do
    run!("mix", ["hex.build", "--output", archive], directory, package_environment())
  end

  defp fetch_released_packages!(source_root, tarballs) do
    lock = Mix.Dep.Lock.read(Path.join(source_root, "mix.lock"))

    Enum.each(@released_packages, fn package ->
      version = locked_hex_version!(lock, package)

      run!(
        "mix",
        ["hex.package", "fetch", Atom.to_string(package), version, "--output", tarballs],
        source_root,
        package_environment()
      )
    end)

    unless locked_version!(source_root, :jason) == @jason_floor do
      run!(
        "mix",
        ["hex.package", "fetch", "jason", @jason_floor, "--output", tarballs],
        source_root,
        package_environment()
      )
    end
  end

  defp locked_version!(source_root, package) do
    source_root
    |> Path.join("mix.lock")
    |> Mix.Dep.Lock.read()
    |> locked_hex_version!(package)
  end

  defp locked_hex_version!(lock, package) do
    case Map.fetch(lock, package) do
      {:ok, {:hex, ^package, version, _, _, _, "hexpm", _}} -> version
      _other -> violation("#{package} is not locked to a public Hex package")
    end
  end

  defp verify_archive_contents!(unpacked, source_root, core_root) do
    Enum.each(@present, &present!(unpacked, &1))
    Enum.each(@absent, &absent!(unpacked, &1))

    unpacked
    |> all_entries()
    |> Enum.each(fn path ->
      relative_path = relative(path, unpacked)

      if Enum.any?(Path.split(relative_path), &(&1 in @forbidden_segments)) do
        violation("packaged archive contains documentation or task path #{relative_path}")
      end
    end)

    unpacked
    |> regular_files()
    |> Enum.each(fn path ->
      content = read_text(path)

      if String.contains?(content, source_root) or String.contains?(content, core_root) do
        violation("archive leaks a repository source path through #{relative(path, unpacked)}")
      end
    end)

    unpacked
    |> all_entries()
    |> Enum.each(fn path ->
      if File.lstat!(path).type == :symlink do
        violation("archive contains symlink #{relative(path, unpacked)}")
      end
    end)
  end

  defp verify_archive_metadata!(outer) do
    metadata_path = Path.join(outer, "metadata.config")

    metadata =
      case :file.consult(String.to_charlist(metadata_path)) do
        {:ok, terms} -> Map.new(terms)
        {:error, reason} -> violation("could not read archive metadata: #{inspect(reason)}")
      end

    expected = %{
      "app" => "wotex_continuum",
      "build_tools" => ["mix"],
      "description" =>
        "Immutable continuum exchange contracts for Elixir and W3C Web of Things systems",
      "elixir" => "~> 1.18",
      "licenses" => ["Apache-2.0"],
      "name" => "wotex_continuum",
      "version" => @package_version
    }

    Enum.each(expected, fn {key, value} ->
      unless decode_metadata(Map.get(metadata, key)) == value do
        violation("archive metadata does not declare exact #{key}")
      end
    end)

    links =
      metadata
      |> Map.fetch!("links")
      |> Enum.map(fn {name, url} -> {decode_metadata(name), decode_metadata(url)} end)
      |> Map.new()

    unless links == %{
             "Changelog" =>
               "https://github.com/wotex-project/wotex/blob/main/packages/wotex-continuum/CHANGELOG.md",
             "GitHub" => "https://github.com/wotex-project/wotex",
             "Specifications" =>
               "https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-continuum"
           } do
      violation("archive metadata does not declare the reviewed public links")
    end

    requirements =
      metadata
      |> Map.fetch!("requirements")
      |> Enum.map(fn requirement ->
        requirement = Map.new(requirement)

        {
          decode_metadata(Map.fetch!(requirement, "name")),
          decode_metadata(Map.fetch!(requirement, "requirement")),
          decode_metadata(Map.fetch!(requirement, "repository")),
          Map.fetch!(requirement, "optional")
        }
      end)
      |> Enum.sort()

    unless requirements == [
             {"jason", "~> 1.4.5", "hexpm", false},
             {"wotex", "~> 0.1", "hexpm", false}
           ] do
      violation("archive metadata does not declare the reviewed runtime requirements")
    end
  end

  defp decode_metadata(value) when is_binary(value), do: value
  defp decode_metadata(values) when is_list(values), do: Enum.map(values, &decode_metadata/1)

  # `mix run` prunes the code path to the project's applications.
  defp write_private_key!(path) do
    Mix.ensure_application!(:public_key)
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    File.write!(path, :public_key.pem_encode([entry]))
  end

  defp build_registry!(source_root, repository, private_key) do
    run!(
      "mix",
      [
        "hex.registry",
        "build",
        repository,
        "--name=hexpm",
        "--private-key=#{private_key}"
      ],
      source_root,
      package_environment()
    )
  end

  defp with_registry(repository, work, function) do
    {:ok, _applications} = Application.ensure_all_started(:inets)

    options = [
      port: 0,
      server_name: ~c"localhost",
      server_root: String.to_charlist(work),
      document_root: String.to_charlist(repository),
      bind_address: {127, 0, 0, 1}
    ]

    case :inets.start(:httpd, options) do
      {:ok, service} ->
        try do
          port = service |> :httpd.info() |> Keyword.fetch!(:port)
          function.("http://127.0.0.1:#{port}")
        after
          :ok = :inets.stop(:httpd, service)
        end

      {:error, reason} ->
        violation("could not start the isolated package registry: #{inspect(reason)}")
    end
  end

  defp write_consumer!(consumer, test_source, additional_dependencies) do
    test_root = Path.join(consumer, "test")
    File.mkdir_p!(test_root)

    dependencies =
      [{:wotex_continuum, "== #{@package_version}"} | additional_dependencies]
      |> inspect(pretty: true, limit: :infinity)

    File.write!(
      Path.join(consumer, "mix.exs"),
      """
      defmodule WotexContinuumArchiveConsumer.MixProject do
        use Mix.Project

        def project do
          [
            app: :wotex_continuum_archive_consumer,
            version: "0.0.0",
            elixir: "~> 1.18",
            deps: #{dependencies}
          ]
        end

        def application, do: [extra_applications: []]
      end
      """
    )

    File.write!(Path.join(test_root, "archive_consumer_test.exs"), test_source)
    File.write!(Path.join(test_root, "test_helper.exs"), "ExUnit.start()\n")
  end

  defp exercise_consumer!(
         consumer,
         repository_url,
         public_key,
         continuum_archive,
         source_root,
         core_root,
         expected_jason
       ) do
    hex_home = Path.join(consumer, ".hex")
    mix_home = Path.join(consumer, ".mix")
    File.mkdir_p!(hex_home)
    File.mkdir_p!(mix_home)

    environment =
      consumer_environment(
        consumer,
        hex_home,
        mix_home,
        source_root,
        core_root,
        expected_jason
      )

    run!(
      "mix",
      [
        "hex.repo",
        "set",
        "hexpm",
        "--url",
        repository_url,
        "--public-key",
        public_key,
        "--no-oauth-exchange"
      ],
      consumer,
      environment
    )

    run!("mix", ["deps.get"], consumer, environment)
    verify_downloaded_archive!(hex_home, continuum_archive)
    verify_hex_lock!(consumer, expected_jason)
    run!("mix", ["deps.get", "--check-locked"], consumer, environment)
    run!("mix", ["compile", "--warnings-as-errors"], consumer, environment)
    run!("mix", ["test", "--warnings-as-errors"], consumer, environment)
    digest(Path.join(consumer, "mix.lock"))
  end

  defp consumer_environment(
         consumer,
         hex_home,
         mix_home,
         source_root,
         core_root,
         expected_jason
       ) do
    [
      {"ERL_LIBS", ""},
      {"HEX_HOME", hex_home},
      {"HEX_NO_UPDATE_CHECK", "1"},
      {"MIX_BUILD_PATH", Path.join(consumer, "_build")},
      {"MIX_DEPS_PATH", Path.join(consumer, "deps")},
      {"MIX_ENV", "test"},
      {"MIX_HOME", mix_home},
      {"MIX_PATH", ""},
      {"WOTEX_ARCHIVE_CONSUMER_ROOT", consumer},
      {"WOTEX_CONTINUUM_SOURCE_ROOT", source_root},
      {"WOTEX_CORE_SOURCE_ROOT", core_root},
      {"WOTEX_EXPECTED_JASON_VERSION", expected_jason},
      {"WOTEX_PATH_DEPS", nil}
    ]
  end

  defp verify_downloaded_archive!(hex_home, continuum_archive) do
    installed =
      Path.join([
        hex_home,
        "packages",
        "hexpm",
        Path.basename(continuum_archive)
      ])

    unless File.regular?(installed) and digest(installed) == digest(continuum_archive) do
      violation("consumer did not install the exact continuum archive")
    end
  end

  defp verify_hex_lock!(consumer, expected_jason) do
    lock = Mix.Dep.Lock.read(Path.join(consumer, "mix.lock"))

    Enum.each(lock, fn {package, entry} ->
      unless match?({:hex, _, _, _, _, _, "hexpm", _}, entry) do
        violation("consumer lock resolves #{package} outside Hex")
      end
    end)

    for package <- ~w(decimal ex_json_schema jason wotex wotex_continuum)a do
      case Map.fetch(lock, package) do
        {:ok, {:hex, _, _, _, _, _, "hexpm", _}} -> :ok
        _other -> violation("consumer lock does not resolve #{package} through Hex")
      end
    end

    expected_versions = %{
      decimal: "3.1.1",
      ex_json_schema: "0.11.5",
      jason: expected_jason,
      wotex: @core_package_version,
      wotex_continuum: @package_version
    }

    Enum.each(expected_versions, fn {package, version} ->
      case Map.fetch!(lock, package) do
        {:hex, ^package, ^version, _, _, _, "hexpm", _} -> :ok
        _other -> violation("consumer lock does not pin #{package} #{version}")
      end
    end)
  end

  defp unpack!(archive, unpacked) do
    outer = Path.join(Path.dirname(unpacked), "outer")
    File.mkdir_p!(outer)
    File.mkdir_p!(unpacked)

    extract!(archive, outer, [])
    extract!(Path.join(outer, "contents.tar.gz"), unpacked, [:compressed])
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

  defp print_evidence(
         source_root,
         core_root,
         unpacked,
         continuum_archive,
         core_archive,
         consumer_locks
       ) do
    IO.puts("source revision: #{source_identity(source_root)}")
    IO.puts("core source revision: #{source_identity(core_root)}")
    IO.puts("continuum archive sha256: #{digest(continuum_archive)}")
    IO.puts("core candidate archive sha256: #{digest(core_archive)}")
    IO.puts("source lock sha256: #{digest(Path.join(source_root, "mix.lock"))}")
    IO.puts("schema set sha256: #{tree_digest(Path.join(unpacked, "priv/schemas"))}")
    IO.puts("vector set sha256: #{tree_digest(Path.join(unpacked, "priv/vectors"))}")

    IO.puts(
      "package version: #{@package_version}; wire version: #{WotexContinuum.schema_version()}"
    )

    IO.puts("toolchain: Elixir #{System.version()}; OTP #{:erlang.system_info(:otp_release)}")

    Enum.each(consumer_locks, fn {name, lock_digest} ->
      IO.puts("#{name} lock sha256: #{lock_digest}")
    end)

    IO.puts("two independent behavior consumers and one direct-dependency floor consumer passed")
  end

  defp source_identity(root) do
    {revision, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root, stderr_to_stdout: true)
    {status, 0} = System.cmd("git", ["status", "--porcelain"], cd: root, stderr_to_stdout: true)
    suffix = if String.trim(status) == "", do: "", else: "+dirty"
    String.trim(revision) <> suffix
  end

  defp tree_digest(root) do
    root
    |> regular_files()
    |> Enum.reduce(:crypto.hash_init(:sha256), fn path, context ->
      context
      |> :crypto.hash_update(relative(path, root))
      |> :crypto.hash_update(<<0>>)
      |> :crypto.hash_update(File.read!(path))
      |> :crypto.hash_update(<<0>>)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
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

  defp all_entries(root) do
    root
    |> File.ls!()
    |> Enum.sort()
    |> Enum.flat_map(fn entry ->
      path = Path.join(root, entry)

      case File.lstat!(path).type do
        :directory -> [path | all_entries(path)]
        _other -> [path]
      end
    end)
  end

  defp regular_files(root) do
    root
    |> all_entries()
    |> Enum.filter(&(File.lstat!(&1).type == :regular))
  end

  defp read_text(path) do
    case File.read(path) do
      {:ok, content} -> if String.valid?(content), do: content, else: ""
      {:error, _reason} -> ""
    end
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
      violation("#{command} #{Enum.join(arguments, " ")} failed in #{directory}")
    end
  end

  defp package_environment do
    [
      {"ERL_LIBS", ""},
      {"HEX_NO_UPDATE_CHECK", "1"},
      {"MIX_ENV", "prod"},
      {"MIX_PATH", ""},
      {"WOTEX_PATH_DEPS", nil}
    ]
  end

  defp work_directory do
    suffix = 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    directory = Path.join(System.tmp_dir!(), "wotex-continuum-archive.#{suffix}")
    File.mkdir_p!(directory)
    directory
  end

  defp cleanup(work) do
    temporary_root = Path.expand(System.tmp_dir!())
    expanded = Path.expand(work)

    if Path.dirname(expanded) == temporary_root and
         String.starts_with?(Path.basename(expanded), "wotex-continuum-archive.") do
      File.rm_rf!(expanded)
    else
      IO.puts(:stderr, "refusing unsafe archive-check cleanup")
      System.halt(1)
    end
  end

  defp relative(path, root), do: Path.relative_to(path, root)

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

WotexContinuum.CheckArchive.run()
