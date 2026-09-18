defmodule Wotex.Binding.MQTT.Check.Archive do
  @moduledoc false

  @prefix "wotex-binding-mqtt-archive."
  @version "0.1.0"
  @mutable_source ~r/{<<"repository">>,<<"(?:git|path)">>|{<<"path">>/
  # Markdown documentation reaches consumers through HexDocs: no `docs/` tree
  # and no task-tracker path may travel inside an archive.
  @machinery ~r{(^|/)(\.check\.exs|\.claude|\.credo\.exs|\.doctor\.exs|\.git|\.github|\.gitignore|\.tool-versions|AGENTS\.md|CLAUDE\.md|bin|config|cover|coveralls\.json|deps|doc|docs|tasks|mix\.lock|priv/plts|test|_build)(/|$)}
  @required_content ~w(
    .formatter.exs
    CHANGELOG.md
    LICENSE
    NOTICE
    README.md
    mix.exs
  )

  @packages [
    %{app: :wotex, directory: "wotex", archive: "wotex-0.1.0.tar", requires: []},
    %{
      app: :wotex_runtime,
      directory: "wotex-runtime",
      archive: "wotex_runtime-0.1.0.tar",
      requires: [:wotex]
    },
    %{
      app: :wotex_binding_mqtt,
      directory: "wotex-binding-mqtt",
      archive: "wotex_binding_mqtt-0.1.0.tar",
      requires: [:wotex, :wotex_runtime]
    }
  ]

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

  defp verify(root, workspace, work) do
    archive_directory = Path.join(work, "archives")
    package_directory = Path.join(work, "packages")
    consumer = Path.join(work, "reference_consumer")
    File.mkdir_p!(archive_directory)
    File.mkdir_p!(package_directory)

    packages =
      Enum.map(@packages, fn package ->
        source = source_directory(package, root, workspace)
        archive = Path.join(archive_directory, package.archive)
        extracted = Path.join(package_directory, Atom.to_string(package.app))

        source_project!(source, package.app)
        build_once!(source, archive)
        inspect_archive!(archive, package)
        extract_archive!(archive, extracted)

        Map.merge(package, %{
          source: source,
          archive_path: archive,
          extracted: extracted,
          digest: digest(archive),
          revision: revision(source)
        })
      end)

    write_consumer!(consumer, packages)
    exercise_consumer!(consumer)
    report_evidence(packages, consumer)
    :ok
  end

  defp source_directory(%{app: :wotex_binding_mqtt}, root, _), do: root

  defp source_directory(%{directory: directory}, _, workspace),
    do: Path.join(workspace, directory)

  defp source_project!(source, app) do
    mix_file = Path.join(source, "mix.exs")
    unless File.regular?(mix_file), do: violation("missing #{app} source project at #{mix_file}")
  end

  # Every exact archive is built once and the inspected bytes are manually
  # extracted. No second source construction is used for the consumer.
  defp build_once!(source, archive) do
    run!("mix", ["hex.build", "--output", archive], source, release_environment())
    unless File.regular?(archive), do: violation("Hex did not create #{archive}")
  end

  defp inspect_archive!(archive, package) do
    members = outer_members!(archive)
    metadata = member!(members, ~c"metadata.config", archive)
    contents = member!(members, ~c"contents.tar.gz", archive)

    require_metadata!(metadata, ~s({<<"name">>,<<"#{package.app}">>}), archive)
    require_metadata!(metadata, ~s({<<"version">>,<<"#{@version}">>}), archive)
    require_metadata!(metadata, ~s({<<"elixir">>,<<"~> 1.18">>}), archive)
    require_metadata!(metadata, ~s({<<"licenses">>,[<<"Apache-2.0">>]}), archive)
    require_metadata!(metadata, ~s({<<"build_tools">>,[<<"mix">>]}), archive)

    Enum.each(package.requires, fn dependency ->
      requirement =
        ~r/{<<"app">>,<<"#{dependency}">>}.*?{<<"requirement">>,<<"~> 0\.1\.0">>}/s

      unless Regex.match?(requirement, metadata) do
        violation("#{archive} does not pin #{dependency} to ~> 0.1.0")
      end
    end)

    if Regex.match?(@mutable_source, metadata) or String.contains?(metadata, "WOTEX_PATH_DEPS") do
      violation("#{archive} metadata contains a mutable dependency source")
    end

    content_members = content_members!(contents, archive)
    safe_members!(content_members, archive)

    if Enum.any?(content_members, &Regex.match?(@machinery, &1)) do
      violation("#{archive} contains development, local-task, or agent machinery")
    end

    Enum.each(@required_content, fn file ->
      unless file in content_members, do: violation("#{archive} is missing #{file}")
    end)

    unless "mix.exs" in content_members and
             Enum.any?(content_members, &String.starts_with?(&1, "lib/")) do
      violation("#{archive} is missing its Mix project or library sources")
    end

    verify_binding_metadata!(metadata, package.app, archive)
    verify_binding_content!(content_members, package.app, archive)
  end

  defp verify_binding_metadata!(metadata, :wotex_binding_mqtt, archive) do
    for value <- [
          "Immutable MQTT command mapping and caller-owned transport adaptation for W3C Web of Things",
          "https://github.com/wotex-project/wotex",
          "https://github.com/wotex-project/wotex/blob/main/packages/wotex-binding-mqtt/CHANGELOG.md",
          "https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-binding-mqtt"
        ] do
      require_metadata!(metadata, value, archive)
    end
  end

  defp verify_binding_metadata!(_, _, _), do: :ok

  defp verify_binding_content!(members, :wotex_binding_mqtt, archive) do
    for file <- ["lib/wotex/binding/mqtt.ex", "README.md", "CHANGELOG.md"] do
      unless file in members, do: violation("#{archive} is missing #{file}")
    end
  end

  defp verify_binding_content!(_, _, _), do: :ok

  defp outer_members!(archive) do
    case :erl_tar.extract(String.to_charlist(archive), [:memory]) do
      {:ok, members} -> members
      {:error, reason} -> violation("cannot inspect #{archive}: #{inspect(reason)}")
    end
  end

  defp member!(members, name, archive) do
    case List.keyfind(members, name, 0) do
      {^name, content} -> content
      nil -> violation("#{archive} is missing #{List.to_string(name)}")
    end
  end

  defp content_members!(contents, archive) do
    case :erl_tar.extract({:binary, contents}, [:compressed, :memory]) do
      {:ok, members} -> Enum.map(members, fn {name, _} -> List.to_string(name) end)
      {:error, reason} -> violation("cannot inspect #{archive} contents: #{inspect(reason)}")
    end
  end

  defp safe_members!(members, archive) do
    if Enum.any?(members, fn member ->
         Path.type(member) == :absolute or ".." in Path.split(member)
       end) do
      violation("#{archive} contains an unsafe archive member")
    end
  end

  defp require_metadata!(metadata, term, archive) do
    unless String.contains?(metadata, term) do
      violation("#{archive} metadata does not contain #{term}")
    end
  end

  defp extract_archive!(archive, destination) do
    File.mkdir_p!(destination)
    contents = archive |> outer_members!() |> member!(~c"contents.tar.gz", archive)

    case :erl_tar.extract(
           {:binary, contents},
           [:compressed, {:cwd, String.to_charlist(destination)}]
         ) do
      :ok -> :ok
      {:error, reason} -> violation("cannot extract #{archive}: #{inspect(reason)}")
    end
  end

  defp write_consumer!(consumer, packages) do
    File.mkdir_p!(Path.join(consumer, "test"))

    package_paths = Map.new(packages, &{&1.app, &1.extracted})
    live_paths = Enum.map(packages, & &1.source)

    File.write!(Path.join(consumer, "mix.exs"), consumer_mix(package_paths))
    File.write!(Path.join(consumer, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(consumer, "test/archive_reference_consumer_test.exs"),
      consumer_test(package_paths, live_paths)
    )
  end

  defp consumer_mix(paths) do
    """
    defmodule WotexMQTTArchiveConsumer.MixProject do
      use Mix.Project

      def project do
        [
          app: :wotex_mqtt_archive_consumer,
          version: "0.0.0",
          elixir: "~> 1.18",
          deps: deps()
        ]
      end

      def application, do: [extra_applications: []]

      defp deps do
        [
          {:wotex, path: #{inspect(paths.wotex)}, override: true},
          {:wotex_runtime, path: #{inspect(paths.wotex_runtime)}, override: true},
          {:wotex_binding_mqtt, path: #{inspect(paths.wotex_binding_mqtt)}, override: true}
        ]
      end
    end
    """
  end

  defp consumer_test(paths, live_paths) do
    replacements = %{
      "__ARCHIVE_ROOTS__" => inspect(Map.values(paths)),
      "__LIVE_ROOTS__" => inspect(live_paths)
    }

    Enum.reduce(replacements, consumer_test_template(), fn {needle, replacement}, source ->
      String.replace(source, needle, replacement)
    end)
  end

  defp consumer_test_template do
    ~S"""
    defmodule MQTTArchiveConsumer.Client do
      @behaviour Wotex.Binding.MQTT.Client

      alias Wotex.Binding.MQTT.{Command, Delivery}

      @impl true
      def publish(%Command{} = command, execution_context, config) do
        send(config.observer, {:client_publish, command, execution_context.credential})

        case config.mode do
          :publish -> :ok
          {:reject, reason} -> {:error, reason}
          {:raise, message} -> raise message
          _ -> {:error, :not_configured}
        end
      end

      @impl true
      def read(%Command{} = command, timeout, execution_context, config) do
        send(config.observer, {:client_read, command, timeout, execution_context.credential})

        with {:read, payload} <- config.mode,
             {:ok, delivery} <-
               Delivery.new(payload,
                 topic: "things/properties/temperature",
                 qos: 1,
                 retain: true
               ) do
          {:ok, delivery}
        else
          _ -> {:error, :not_configured}
        end
      end

      @impl true
      def subscribe(%Command{} = command, owner, execution_context, config) do
        send(config.observer, {:client_subscribe, command, owner, execution_context.credential})

        with {:stream, payload} <- config.mode,
             {:ok, delivery} <-
               Delivery.new(payload,
                 topic: "things/properties/temperature",
                 qos: 1,
                 retain: false
               ) do
          handle = {:archive_handle, make_ref()}
          send(owner, {:wotex_transport_frame, delivery})
          {:ok, handle}
        else
          _ -> {:error, :not_configured}
        end
      end

      @impl true
      def unsubscribe(handle, %Command{} = command, execution_context, config) do
        send(config.observer, {:client_unsubscribe, handle, command, execution_context.credential})
        :ok
      end
    end

    defmodule MQTTArchiveConsumer.Credentials do
      @behaviour Wotex.Runtime.Credentials

      @impl true
      def resolve(security, form, context, config) do
        send(config.observer, {:credential_resolve, security, form, context})
        {:ok, config.credential}
      end
    end

    defmodule MQTTArchiveReferenceConsumerTest do
      use ExUnit.Case, async: false

      alias MQTTArchiveConsumer.{Client, Credentials}
      alias Wotex.Binding.MQTT
      alias Wotex.Binding.MQTT.{Command, JSON, Topic, Transport, TransportConfig}
      alias Wotex.Runtime.{ConsumedThing, Context, Error, Result, Subscription}

      @archive_roots __ARCHIVE_ROOTS__
      @live_roots __LIVE_ROOTS__
      @apps [:wotex, :wotex_runtime, :wotex_binding_mqtt]
      @modules [Wotex, Wotex.Runtime.ConsumedThing, Wotex.Binding.MQTT]

      test "WBM-A01 exact archives are the only Wotex compile and load sources" do
        build_root = Path.expand("_build", File.cwd!())

        Enum.zip(@apps, @modules)
        |> Enum.each(fn {app, module} ->
          assert Application.load(app) in [:ok, {:error, {:already_loaded, app}}]
          assert Application.spec(app, :mod) in [nil, [], :undefined]

          source = module.module_info(:compile)[:source] |> List.to_string() |> Path.expand()
          beam = module |> :code.which() |> List.to_string() |> Path.expand()

          assert Enum.any?(@archive_roots, &inside?(source, &1)),
                 "compile source is outside extracted archives: #{source}"

          assert inside?(beam, build_root)
          refute Enum.any?(@live_roots, &inside?(source, &1))
          refute Enum.any?(@live_roots, &inside?(beam, &1))
        end)

        code_paths = Enum.map(:code.get_path(), &(&1 |> List.to_string() |> Path.expand()))

        refute Enum.any?(code_paths, fn path ->
                 Enum.any?(@live_roots, &inside?(path, &1))
               end)
      end

      test "WBM-A02 a PUBLISH crosses Runtime with immutable command values" do
        context = Context.new!(request_id: "archive-publish")

        assert {:ok,
                %Result{
                  operation: :writeproperty,
                  status: :accepted,
                  payload: nil,
                  metadata: %{binding: :mqtt, control_packet: :publish, qos: 1}
                }} = ConsumedThing.write_property(consumed(:publish), "temperature", 21, context)

        assert_receive {:credential_resolve, %{names: ["nosec"]}, %Wotex.Form{}, ^context}
        assert_receive {:client_publish, %Command{} = command, :archive_credential}
        assert Command.topic(command) == "things/properties/temperature"
        assert Command.payload(command) == "21"
        assert Command.qos(command) == 1
        refute inspect(command) =~ "archive_credential"
      end

      test "WBM-A03 a retained finite read crosses Runtime and returns delivery metadata" do
        context = Context.new!(request_id: "archive-read")

        assert {:ok,
                %Result{
                  operation: :readproperty,
                  status: :ok,
                  payload: %{"value" => 21},
                  metadata: %{
                    binding: :mqtt,
                    control_packet: :subscribe,
                    delivery_qos: 1,
                    delivery_retained: true,
                    topic: "things/properties/temperature"
                  }
                }} =
                 :read
                 |> consumed(payload: ~s({"value":21}), read_timeout: 37)
                 |> ConsumedThing.read_property("temperature", context)

        assert_receive {:client_read, %Command{} = command, 37, :archive_credential}
        assert Command.filters(command) == ["things/properties/temperature"]
        assert Command.retain?(command)
      end

      test "WBM-A04 a consumer Supervisor owns paired subscribe and unsubscribe Forms" do
        consumed = consumed(:stream, payload: ~s({"value":22}))
        context = Context.new!(request_id: "archive-subscription")

        assert {:ok, child_spec} =
                 ConsumedThing.observation_child_spec(consumed, "temperature", context,
                   id: :archive_observation,
                   receiver: self(),
                   restart: :temporary
                 )

        assert {:ok, supervisor} = Supervisor.start_link([child_spec], strategy: :one_for_one)

        [{:archive_observation, owner, :worker, [Wotex.Runtime.Subscription]}] =
          Supervisor.which_children(supervisor)

        assert_receive {:client_subscribe, %Command{} = command, ^owner, :archive_credential}
        assert Command.filters(command) == ["things/properties/+"]

        assert_receive {:wotex_runtime, :archive_observation,
                        {:ok, %{"value" => 22},
                         %{
                           operation: :observeproperty,
                           topic: "things/properties/temperature",
                           qos: 1,
                           retained: false
                         }}}

        assert :ok = Subscription.stop(owner)

        assert_receive {:client_unsubscribe, {:archive_handle, _}, %Command{} = close_command,
                        :archive_credential}

        assert Command.operation(close_command) == :unobserveproperty
        assert Command.filters(close_command) == ["things/properties/+"]
        refute Process.alive?(owner)
        Supervisor.stop(supervisor)
      end

      test "WBM-A05 exact payload, Topic, and filter-cardinality bounds survive packaging" do
        assert {:ok, nil} = JSON.decode("null", 4)
        assert {:error, %{code: :received_payload_too_large}} = JSON.decode("false", 4)

        exact_topic = String.duplicate("t", 65_535)
        assert :ok = Topic.validate_name(exact_topic)
        assert {:error, %{code: :invalid_topic_name}} = Topic.validate_name(exact_topic <> "t")

        exact_filters = Enum.map(1..256, &"things/#{&1}")
        assert {:ok, ^exact_filters} = Topic.normalize_filters(exact_filters)

        assert {:error, %{code: :too_many_topic_filters, details: %{max_filters: 256}}} =
                 Topic.normalize_filters(Enum.concat(exact_filters, ["things/257"]))
      end

      test "WBM-A06 returned and raised supplied-client failures stay redacted" do
        secret = "archive-nested-client-secret"
        nested = {:outer, [%{credential: secret}, {:connection, self(), make_ref()}]}

        for mode <- [{:reject, nested}, {:raise, secret}] do
          assert {:error, %Error{} = error} =
                   mode
                   |> consumed(credential: secret)
                   |> ConsumedThing.write_property(
                     "temperature",
                     21,
                     Context.new!(request_id: "archive-redaction")
                   )

          refute encoded(error) =~ secret
          assert_receive {:client_publish, %Command{}, ^secret}
        end
      end

      defp consumed(mode, opts \\ []) do
        client_config = %{observer: self(), mode: normalized_mode(mode, opts)}

        config_options =
          []
          |> maybe_put(opts, :read_timeout)
          |> maybe_put(opts, :max_payload_bytes)

        {:ok, config} = TransportConfig.new(Client, client_config, config_options)

        credentials =
          {Credentials,
           %{
             observer: self(),
             credential: Keyword.get(opts, :credential, :archive_credential)
           }}

        {:ok, value} =
          ConsumedThing.new(thing_description(),
            profiles: [MQTT.profile()],
            transports: %{mqtt: {Transport, config}},
            credentials: credentials
          )

        value
      end

      defp normalized_mode(:read, opts), do: {:read, Keyword.fetch!(opts, :payload)}
      defp normalized_mode(:stream, opts), do: {:stream, Keyword.fetch!(opts, :payload)}
      defp normalized_mode(mode, _), do: mode

      defp maybe_put(target, source, key) do
        if Keyword.has_key?(source, key), do: Keyword.put(target, key, source[key]), else: target
      end

      defp thing_description do
        {:ok, td} =
          Wotex.ThingDescription.from_map(%{
            "@context" => Wotex.td_context_1_1(),
            "id" => "urn:example:mqtt-archive-consumer",
            "title" => "MQTT archive consumer",
            "securityDefinitions" => %{"nosec" => %{"scheme" => "nosec"}},
            "security" => ["nosec"],
            "properties" => %{
              "temperature" => %{
                "type" => "number",
                "observable" => true,
                "forms" => [
                  %{
                    "href" => "mqtt://broker.example",
                    "contentType" => "application/json",
                    "op" => "readproperty",
                    "mqv:qos" => "1",
                    "mqv:retain" => true,
                    "mqv:filter" => "things/properties/temperature"
                  },
                  %{
                    "href" => "mqtt://broker.example",
                    "contentType" => "application/json",
                    "op" => "writeproperty",
                    "mqv:qos" => "1",
                    "mqv:topic" => "things/properties/temperature"
                  },
                  %{
                    "href" => "mqtt://broker.example",
                    "contentType" => "application/json",
                    "op" => ["observeproperty", "unobserveproperty"],
                    "mqv:qos" => "1",
                    "mqv:filter" => "things/properties/+"
                  }
                ]
              }
            }
          })

        td
      end

      defp encoded(term), do: :erlang.term_to_binary(term)

      defp inside?(path, root) do
        expanded_path = canonical(path)
        expanded_root = canonical(root)
        expanded_path == expanded_root or String.starts_with?(expanded_path, expanded_root <> "/")
      end

      defp canonical(path) do
        path
        |> Path.expand()
        |> String.replace_prefix("/private/var/", "/var/")
      end
    end
    """
  end

  defp exercise_consumer!(consumer) do
    environment = isolated_environment()
    run!("mix", ["deps.get"], consumer, environment)
    run!("mix", ["deps.get", "--check-locked"], consumer, environment)
    run!("mix", ["test", "--no-start", "--warnings-as-errors"], consumer, environment)
  end

  defp report_evidence(packages, consumer) do
    Enum.each(packages, fn package ->
      IO.puts("exact archive #{package.app} #{package.revision}: sha256=#{package.digest}")
    end)

    lock = Path.join(consumer, "mix.lock")
    IO.puts("isolated consumer lock: sha256=#{digest(lock)}")
    IO.puts("archive/reference vectors: WBM-A01..WBM-A06")
    IO.puts("live Wotex source/code paths in isolated consumer: none")
    IO.puts("application callbacks in exact Wotex archives: none")
  end

  defp revision(source) do
    {output, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: source, stderr_to_stdout: true)
    String.trim(output)
  end

  defp release_environment do
    [
      {"WOTEX_PATH_DEPS", nil},
      {"MIX_ENV", "dev"},
      {"ERL_LIBS", nil},
      {"MIX_PATH", nil}
    ]
  end

  defp isolated_environment do
    [
      {"WOTEX_PATH_DEPS", nil},
      {"MIX_ENV", "test"},
      {"ERL_LIBS", nil},
      {"MIX_PATH", nil},
      {"MIX_BUILD_PATH", nil},
      {"MIX_DEPS_PATH", nil}
    ]
  end

  defp run!(command, arguments, directory, environment) do
    options = [
      cd: directory,
      env: environment,
      into: IO.stream(),
      stderr_to_stdout: true
    ]

    {_output, status} = System.cmd(command, arguments, options)
    unless status == 0, do: violation("#{command} #{Enum.join(arguments, " ")} failed")
  end

  defp digest(path) do
    :sha256
    |> :crypto.hash(File.read!(path))
    |> Base.encode16(case: :lower)
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

  defp violation(message), do: throw({:violation, message})
  defp report(:ok), do: :ok

  defp report({:violation, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Binding.MQTT.Check.Archive.main()
