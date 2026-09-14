defmodule Wotex.Modbus.Check.Archive do
  @moduledoc false

  @version "0.1.0"
  @candidate_packages %{wotex: "0.1.0", wotex_runtime: "0.1.0", wotex_modbus: @version}
  @released_packages [:decimal, :ex_json_schema, :jason, :telemetry]

  @outer ["VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"]

  @present [
    "mix.exs",
    "LICENSE",
    "NOTICE",
    "README.md",
    "SECURITY.md",
    "GOVERNANCE.md",
    "docs/plans/wotex-modbus-completion.md",
    "docs/specs/WMB.00-library-contract.md",
    "docs/specs/WMB.10-software-contract.md",
    "docs/specs/WMB.11-standalone-client-and-preservation.md",
    "docs/specs/WMB.12-wotex-integration.md",
    "docs/specs/WMB.13-native-build-and-software-evidence.md",
    "docs/specs/WMB.14-release-candidate-dossier.md",
    "docs/specs/catalogue.yaml",
    "lib/wotex/modbus.ex",
    "lib/wotex/modbus/transport.ex"
  ]

  @absent [
    ".check.exs",
    ".claude",
    ".elixir_ls",
    ".git",
    ".github",
    "AGENTS.md",
    "CLAUDE.md",
    "_build",
    "bin",
    "cover",
    "deps",
    "doc",
    "docs/tasks",
    "priv/plts",
    "test"
  ]

  @consumer_verification ~S"""
  defmodule WotexModbusArchiveCredentials do
    @behaviour Wotex.Runtime.Credentials

    @impl Wotex.Runtime.Credentials
    def resolve(
          %{names: ["none"], definitions: %{"none" => %{"scheme" => "nosec"}}},
          _form,
          _context,
          nil
        ),
        do: {:ok, nil}

    def resolve(_, _, _, _), do: {:error, :unexpected_security}
  end

  defmodule WotexModbusArchiveVerification do
    alias Wotex.Modbus.{Codec, Command, Mapping}
    alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Result}

    def run do
      assert_application_free!()
      assert_isolated_code!()
      assert_pure_boundaries!()
      assert_runtime_read!()
      assert_runtime_write!()
      assert_runtime_action!()
      assert_invalid_route!()
      IO.puts("candidate archive consumer exercised native and Runtime Modbus boundaries")
    end

    defp assert_application_free! do
      for application <- [:wotex, :wotex_runtime, :wotex_modbus] do
        unless Application.load(application) in [:ok, {:error, {:already_loaded, application}}] do
          raise "cannot load candidate application #{application}"
        end

        unless Application.spec(application, :mod) in [nil, [], :undefined] do
          raise "candidate application #{application} defines a callback"
        end
      end
    end

    defp assert_isolated_code! do
      consumer = System.fetch_env!("WOTEX_ARCHIVE_CONSUMER_ROOT")

      source_roots =
        ~w(WOTEX_SOURCE_ROOT WOTEX_RUNTIME_SOURCE_ROOT WOTEX_CORE_SOURCE_ROOT)
        |> Enum.map(&System.fetch_env!/1)

      for module <- [Wotex, Wotex.Runtime.ConsumedThing, Wotex.Modbus, Jason] do
        beam = module |> :code.which() |> List.to_string()

        unless String.starts_with?(beam, Path.join(consumer, "_build")) do
          raise "#{inspect(module)} did not load from the isolated consumer"
        end

        if Enum.any?(source_roots, &String.contains?(beam, &1)) do
          raise "#{inspect(module)} loaded from a source checkout"
        end
      end
    end

    defp assert_pure_boundaries! do
      profile = Wotex.Modbus.profile()
      unless BindingProfile.id(profile) == :modbus, do: raise("wrong archive profile")

      {:ok, command} = Command.new(:read_holding_registers, 10, 1, 1)
      {:ok, bytes} = Codec.encode(command, 7)

      unless bytes == <<7::16, 0::16, 6::16, 1, 3, 0, 10, 0, 1>> do
        raise "archive command encoding changed"
      end

      form = %{
        "href" => "modbus+tcp://127.0.0.1/1/11?quantity=1",
        "modv:entity" => "HoldingRegister",
        "example:extension" => %{"retain" => [false, 0, nil]}
      }

      {:ok, mapping} = Mapping.command(form, :readproperty)
      unless mapping.command == command, do: raise("archive mapping changed")

      unless Wotex.Form.to_map(mapping.form)["example:extension"] ==
               %{"retain" => [false, 0, nil]} do
        raise "archive mapping lost a Form extension"
      end
    end

    defp assert_runtime_read! do
      {peer, port} =
        start_peer(fn 1, <<3, 0, 10, 0, 1>> ->
          <<3, 2, 0, 42>>
        end)

      consumed = consumed(:property, property_form(port))
      {:ok, context} = Context.new(request_id: "archive-read")

      {:ok,
       %Result{
         request_id: "archive-read",
         operation: :readproperty,
         payload: [42],
         metadata: %{function: 3}
       }} = ConsumedThing.read_property(consumed, "reading", context)

      :ok = Task.await(peer, 3000)
    end

    defp assert_runtime_write! do
      {peer, port} =
        start_peer(fn 1, <<6, 0, 10, 0, 42>> ->
          <<6, 0, 10, 0, 42>>
        end)

      consumed = consumed(:property, property_form(port))
      {:ok, context} = Context.new(request_id: "archive-write")

      {:ok,
       %Result{
         request_id: "archive-write",
         operation: :writeproperty,
         payload: :written,
         metadata: %{function: 6}
       }} = ConsumedThing.write_property(consumed, "reading", 42, context)

      :ok = Task.await(peer, 3000)
    end

    defp assert_runtime_action! do
      {peer, port} =
        start_peer(fn 1, <<6, 0, 10, 0, 42>> ->
          <<6, 0, 10, 0, 42>>
        end)

      form = %{
        "href" => "modbus+tcp://127.0.0.1:#{port}/1/11?quantity=1",
        "modv:function" => "writeSingleHoldingRegister"
      }

      consumed = consumed(:action, form)
      {:ok, context} = Context.new(request_id: "archive-action")

      {:ok,
       %Result{
         request_id: "archive-action",
         operation: :invokeaction,
         payload: :written,
         metadata: %{function: 6}
       }} = ConsumedThing.invoke_action(consumed, "write", 42, context)

      :ok = Task.await(peer, 3000)
    end

    defp assert_invalid_route! do
      consumed =
        consumed(:property, %{
          "href" => "modbus+tcp://localhost/1/11?quantity=1",
          "modv:entity" => "HoldingRegister"
        })

      {:ok, context} = Context.new(request_id: "archive-invalid")

      {:error,
       %Wotex.Runtime.Error{
         class: :permanent,
         details: %{cause: %{code: :invalid_host}}
       }} = ConsumedThing.read_property(consumed, "reading", context)
    end

    defp property_form(port) do
      %{
        "href" => "modbus+tcp://127.0.0.1:#{port}/1/11?quantity=1",
        "modv:entity" => "HoldingRegister"
      }
    end

    defp consumed(kind, form) do
      affordances =
        case kind do
          :property -> %{"properties" => %{"reading" => %{"forms" => [form]}}}
          :action -> %{"actions" => %{"write" => %{"forms" => [form]}}}
        end

      input =
        Map.merge(
          %{
            "@context" => Wotex.td_context_1_1(),
            "title" => "Candidate archive Modbus Thing",
            "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
            "security" => ["none"]
          },
          affordances
        )

      {:ok, description} = Wotex.ThingDescription.from_map(input)

      {:ok, consumed} =
        ConsumedThing.new(description,
          profiles: [Wotex.Modbus.profile()],
          transports: %{modbus: {Wotex.Modbus.Transport, [timeout: 1000]}},
          credentials: {WotexModbusArchiveCredentials, nil}
        )

      consumed
    end

    defp start_peer(handler) do
      {:ok, listener} =
        :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

      {:ok, {_, port}} = :inet.sockname(listener)

      peer =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 2000)
          :ok = :gen_tcp.close(listener)

          try do
            {:ok, <<transaction::16, 0::16, length::16>>} = :gen_tcp.recv(socket, 6, 2000)
            {:ok, <<unit, payload::binary>>} = :gen_tcp.recv(socket, length, 2000)
            response = handler.(unit, payload)

            :ok =
              :gen_tcp.send(
                socket,
                <<transaction::16, 0::16, byte_size(response) + 1::16, unit,
                  response::binary>>
              )
          after
            :gen_tcp.close(socket)
          end
        end)

      {peer, port}
    end
  end

  WotexModbusArchiveVerification.run()
  """

  @spec main() :: :ok
  def main do
    source_root = File.cwd!()

    roots = %{
      wotex: dependency_source!(:wotex),
      wotex_runtime: dependency_source!(:wotex_runtime),
      wotex_modbus: source_root
    }

    work = Path.join(System.tmp_dir!(), "wotex-modbus-archive.#{unique()}")

    result =
      try do
        File.mkdir_p!(work)
        verify(roots, work)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        File.rm_rf!(work)
      end

    report(result)
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp dependency_source!(dependency) do
    case Map.fetch(Mix.Project.deps_paths(), dependency) do
      {:ok, path} -> Path.expand(path)
      :error -> violation("development dependency #{dependency} is not resolved")
    end
  end

  defp verify(roots, work) do
    repository = Path.join(work, "repository")
    tarballs = Path.join(repository, "tarballs")
    unpacked = Path.join(work, "unpacked")
    outer = Path.join(work, "outer")
    consumer = Path.join(work, "consumer")
    private_key = Path.join(work, "registry-private.pem")

    archives =
      Map.new(@candidate_packages, fn {package, version} ->
        {package, Path.join(tarballs, "#{package}-#{version}.tar")}
      end)

    File.mkdir_p!(tarballs)

    Enum.each(archives, fn {package, archive} ->
      build_archive!(Map.fetch!(roots, package), archive)
    end)

    fetch_released_packages!(Map.fetch!(roots, :wotex_modbus), tarballs)
    unpack!(Map.fetch!(archives, :wotex_modbus), outer, unpacked)
    verify_outer!(outer)
    verify_metadata!(outer)
    verify_contents!(unpacked, Map.values(roots))
    verify_notice!(unpacked)
    write_private_key!(private_key)
    build_registry!(Map.fetch!(roots, :wotex_modbus), repository, private_key)

    lock_digest =
      with_registry(repository, work, fn repository_url ->
        write_consumer!(consumer)
        exercise_consumer!(consumer, repository_url, repository, archives, roots)
      end)

    IO.puts("wotex archive sha256: #{digest(Map.fetch!(archives, :wotex))}")
    IO.puts("wotex_runtime archive sha256: #{digest(Map.fetch!(archives, :wotex_runtime))}")
    IO.puts("wotex_modbus archive sha256: #{digest(Map.fetch!(archives, :wotex_modbus))}")
    IO.puts("consumer lock sha256: #{lock_digest}")
    IO.puts("candidate archives installed through an isolated Hex registry")

    :ok
  end

  defp build_archive!(root, archive) do
    run!("mix", ["hex.build", "--output", archive], root, package_environment())

    unless File.regular?(archive) do
      violation("Hex archive build did not produce #{Path.basename(archive)}")
    end
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
  end

  defp locked_hex_version!(lock, package) do
    case Map.fetch(lock, package) do
      {:ok, {:hex, ^package, version, _, _, _, "hexpm", _}} -> version
      _ -> violation("#{package} is not locked to a public Hex package")
    end
  end

  defp unpack!(archive, outer, unpacked) do
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
      {:error, reason} -> violation("cannot extract #{archive}: #{inspect(reason)}")
    end
  end

  defp verify_outer!(outer) do
    Enum.each(@outer, fn entry ->
      unless File.regular?(Path.join(outer, entry)) do
        violation("archive is missing #{entry}")
      end
    end)
  end

  defp verify_contents!(unpacked, source_roots) do
    Enum.each(@present, fn entry ->
      unless File.regular?(Path.join(unpacked, entry)) do
        violation("package contents are missing #{entry}")
      end
    end)

    Enum.each(@absent, fn entry ->
      if File.exists?(Path.join(unpacked, entry)) do
        violation("package contains development state #{entry}")
      end
    end)

    Enum.each(all_entries(unpacked), fn path ->
      if File.lstat!(path).type == :symlink do
        violation("package contains symlink #{Path.relative_to(path, unpacked)}")
      end
    end)

    unpacked
    |> regular_files()
    |> Enum.each(fn path ->
      content = File.read!(path)

      if Enum.any?(source_roots, &String.contains?(content, &1)) do
        violation("package leaks a repository path through #{Path.relative_to(path, unpacked)}")
      end
    end)
  end

  defp verify_notice!(unpacked) do
    expected =
      "Wotex Modbus\nCopyright 2026 Wotex contributors\n\n" <>
        "Licensed under the Apache License, Version 2.0.\n"

    unless File.read!(Path.join(unpacked, "NOTICE")) == expected do
      violation("package NOTICE does not identify Wotex Modbus exactly")
    end
  end

  defp verify_metadata!(outer) do
    metadata_path = Path.join(outer, "metadata.config")

    metadata =
      case :file.consult(String.to_charlist(metadata_path)) do
        {:ok, terms} -> Map.new(terms)
        {:error, reason} -> violation("cannot read archive metadata: #{inspect(reason)}")
      end

    expected = %{
      "app" => "wotex_modbus",
      "build_tools" => ["mix"],
      "description" =>
        "Consumer-neutral Modbus protocol values, operations and Web of Things Form mapping",
      "elixir" => "~> 1.18",
      "licenses" => ["Apache-2.0"],
      "name" => "wotex_modbus",
      "version" => @version
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
             "Changelog" => "https://github.com/wotex-project/wotex-modbus/blob/main/CHANGELOG.md",
             "Documentation" => "https://hexdocs.pm/wotex_modbus",
             "Project" => "https://wotex.io",
             "Source" => "https://github.com/wotex-project/wotex-modbus",
             "W3C Thing Description 1.1" =>
               "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/"
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
             {"jason", "~> 1.4", "hexpm", false},
             {"telemetry", "~> 1.3", "hexpm", false},
             {"wotex", "~> 0.1.0", "hexpm", false},
             {"wotex_runtime", "~> 0.1.0", "hexpm", false}
           ] do
      violation("archive metadata does not declare the reviewed runtime requirements")
    end
  end

  defp decode_metadata(value) when is_binary(value), do: value
  defp decode_metadata(values) when is_list(values), do: Enum.map(values, &decode_metadata/1)

  defp write_private_key!(path) do
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
    {:ok, _} = Application.ensure_all_started(:inets)

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
        violation("cannot start isolated package registry: #{inspect(reason)}")
    end
  end

  defp write_consumer!(consumer) do
    File.mkdir_p!(consumer)

    File.write!(
      Path.join(consumer, "mix.exs"),
      """
      defmodule WotexModbusArchiveConsumer.MixProject do
        use Mix.Project

        def project do
          [
            app: :wotex_modbus_archive_consumer,
            version: "0.0.0",
            elixir: "~> 1.18",
            deps: [{:wotex_modbus, "== #{@version}"}]
          ]
        end

        def application, do: [extra_applications: []]
      end
      """
    )

    File.write!(Path.join(consumer, "verify.exs"), @consumer_verification)
  end

  defp exercise_consumer!(consumer, repository_url, repository, archives, roots) do
    hex_home = Path.join(consumer, ".hex")
    mix_home = Path.join(consumer, ".mix")
    File.mkdir_p!(hex_home)
    File.mkdir_p!(mix_home)

    environment = consumer_environment(consumer, hex_home, mix_home, roots)

    run!(
      "mix",
      [
        "hex.repo",
        "set",
        "hexpm",
        "--url",
        repository_url,
        "--public-key",
        Path.join(repository, "public_key"),
        "--no-oauth-exchange"
      ],
      consumer,
      environment
    )

    run!("mix", ["deps.get"], consumer, environment)
    verify_installed_archives!(hex_home, archives)
    verify_hex_lock!(consumer, Map.fetch!(roots, :wotex_modbus))
    run!("mix", ["deps.get", "--check-locked"], consumer, environment)
    run!("mix", ["compile", "--warnings-as-errors"], consumer, environment)
    run!("mix", ["run", "--no-start", "--no-compile", "verify.exs"], consumer, environment)
    digest(Path.join(consumer, "mix.lock"))
  end

  defp consumer_environment(consumer, hex_home, mix_home, roots) do
    [
      {"ERL_LIBS", ""},
      {"HEX_HOME", hex_home},
      {"HEX_NO_UPDATE_CHECK", "1"},
      {"MIX_BUILD_PATH", Path.join(consumer, "_build")},
      {"MIX_DEPS_PATH", Path.join(consumer, "deps")},
      {"MIX_ENV", "prod"},
      {"MIX_HOME", mix_home},
      {"MIX_PATH", ""},
      {"WOTEX_ARCHIVE_CONSUMER_ROOT", consumer},
      {"WOTEX_CORE_SOURCE_ROOT", Map.fetch!(roots, :wotex)},
      {"WOTEX_RUNTIME_SOURCE_ROOT", Map.fetch!(roots, :wotex_runtime)},
      {"WOTEX_SOURCE_ROOT", Map.fetch!(roots, :wotex_modbus)},
      {"WOTEX_PATH_DEPS", nil}
    ]
  end

  defp verify_installed_archives!(hex_home, archives) do
    Enum.each(archives, fn {_package, archive} ->
      installed = Path.join([hex_home, "packages", "hexpm", Path.basename(archive)])

      unless File.regular?(installed) and digest(installed) == digest(archive) do
        violation("consumer did not install exact archive #{Path.basename(archive)}")
      end
    end)
  end

  defp verify_hex_lock!(consumer, source_root) do
    lock = Mix.Dep.Lock.read(Path.join(consumer, "mix.lock"))
    source_lock = Mix.Dep.Lock.read(Path.join(source_root, "mix.lock"))

    expected =
      Map.merge(
        @candidate_packages,
        Map.new(@released_packages, &{&1, locked_hex_version!(source_lock, &1)})
      )

    unless Map.keys(lock) |> Enum.sort() == Map.keys(expected) |> Enum.sort() do
      violation("consumer lock contains an unexpected dependency graph")
    end

    Enum.each(expected, fn {package, version} ->
      case Map.fetch!(lock, package) do
        {:hex, ^package, ^version, _, _, _, "hexpm", _} -> :ok
        _ -> violation("consumer lock does not pin #{package} #{version} through Hex")
      end
    end)
  end

  defp package_environment do
    command_environment([{"MIX_ENV", "prod"}])
  end

  defp command_environment(overrides) do
    %{
      "ERL_LIBS" => "",
      "HEX_NO_UPDATE_CHECK" => "1",
      "MIX_PATH" => "",
      "WOTEX_PATH_DEPS" => nil
    }
    |> Map.merge(Map.new(overrides))
    |> Map.to_list()
  end

  defp all_entries(root),
    do: Path.wildcard(Path.join(root, "**/*"), match_dot: true)

  defp regular_files(root), do: Enum.filter(all_entries(root), &File.regular?/1)

  defp digest(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
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
      violation("#{command} #{Enum.join(arguments, " ")} failed in #{directory}")
    end
  end

  defp violation(message), do: throw({:violation, message})

  defp report(:ok), do: :ok

  defp report({:violation, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Modbus.Check.Archive.main()
