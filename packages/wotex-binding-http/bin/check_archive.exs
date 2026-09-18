defmodule WotexBindingHTTP.Check.Archive do
  @moduledoc false

  @prefix "wotex-binding-http-archive."
  @version "0.1.0"
  @mutable_source ~r/{<<"repository">>,<<"(?:git|path)">>|{<<"path">>/
  # Markdown documentation reaches consumers through HexDocs: no `docs/` tree
  # and no task-tracker path may travel inside an archive.
  @machinery ~r{(^|/)(\.check\.exs|\.claude|\.credo\.exs|\.doctor\.exs|\.git|\.github|\.tool-versions|AGENTS\.md|CLAUDE\.md|bin|config|cover|coveralls\.json|deps|doc|docs|tasks|mix\.lock|priv/plts|test|_build)(/|$)}
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
      app: :wotex_binding_http,
      directory: "wotex-binding-http",
      archive: "wotex_binding_http-0.1.0.tar",
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

  defp source_directory(%{app: :wotex_binding_http}, root, _workspace), do: root

  defp source_directory(%{directory: directory}, _root, workspace),
    do: Path.join(workspace, directory)

  defp source_project!(source, app) do
    mix_file = Path.join(source, "mix.exs")

    unless File.regular?(mix_file) do
      violation("missing #{app} source project at #{mix_file}")
    end
  end

  # Each exact archive is built once, then the inspected bytes are manually
  # extracted. There is no second `hex.build --unpack` source construction.
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
  end

  defp verify_binding_metadata!(metadata, :wotex_binding_http, archive) do
    for value <- [
          "Caller-owned HTTP and Server-Sent Events binding for Wotex Runtime",
          "https://github.com/wotex-project/wotex",
          "https://github.com/wotex-project/wotex/blob/main/packages/wotex-binding-http/CHANGELOG.md",
          "https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-binding-http"
        ] do
      require_metadata!(metadata, value, archive)
    end
  end

  defp verify_binding_metadata!(_metadata, _app, _archive), do: :ok

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
    members = outer_members!(archive)
    contents = member!(members, ~c"contents.tar.gz", archive)

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
    defmodule WotexArchiveReferenceConsumer.MixProject do
      use Mix.Project

      def project do
        [
          app: :wotex_archive_reference_consumer,
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
          {:wotex_binding_http, path: #{inspect(paths.wotex_binding_http)}, override: true}
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
    defmodule ArchiveReferenceConsumer.Client do
      @behaviour Wotex.Binding.HTTP.Client

      alias Wotex.Binding.HTTP.{Request, Response}
      alias Wotex.Binding.HTTP.SSE.Event

      @impl true
      def request(%Request{} = request, credential, config) do
        send(config.observer, {:client_request, request, credential})

        case config.mode do
          {:body, body} -> response(200, body, [{"Content-Type", "application/json"}])
          :redirect -> response(302, "", [{"Location", "https://other.example/private"}])
          {:reject, reason} -> {:error, reason}
          {:raise, message} -> raise message
          _ -> {:error, :not_configured}
        end
      end

      @impl true
      def subscribe(%Request{} = request, credential, owner, config) do
        send(config.observer, {:client_subscribe, request, credential, owner})
        {:ok, event} = Event.new(config.event, event: "temperature", id: "archive-event")
        send(owner, {:wotex_transport_frame, event})
        {:ok, handshake} = response(200, "", [{"Content-Type", "text/event-stream"}])
        {:ok, {:archive_stream, make_ref()}, handshake}
      end

      @impl true
      def close(handle, config) do
        send(config.observer, {:client_close, handle})
        :ok
      end

      defp response(status, body, headers) do
        Response.new(status, headers, body)
      end
    end

    defmodule ArchiveReferenceConsumer.Credentials do
      @behaviour Wotex.Runtime.Credentials

      @impl true
      def resolve(security, form, context, config) do
        send(config.observer, {:credential_resolve, security, form, context})
        {:ok, config.credential}
      end
    end

    defmodule ArchiveReferenceConsumerTest do
      use ExUnit.Case, async: false

      alias ArchiveReferenceConsumer.{Client, Credentials}
      alias Wotex.Binding.HTTP
      alias Wotex.Binding.HTTP.Request
      alias Wotex.Runtime.{ConsumedThing, Context, Error, Result, Subscription}

      @archive_roots __ARCHIVE_ROOTS__
      @live_roots __LIVE_ROOTS__
      @apps [:wotex, :wotex_runtime, :wotex_binding_http]
      @modules [Wotex, Wotex.Runtime.ConsumedThing, Wotex.Binding.HTTP]

      test "WBH-A01 exact archives are the only Wotex compile and load sources" do
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

      test "WBH-A02 an accepted finite HTTP request runs through Runtime" do
        consumed = consumed({:body, "21"})
        context = Context.new!(request_id: "archive-request")

        assert {:ok, %Result{payload: 21, operation: :readproperty, status: :ok} = result} =
                 ConsumedThing.read_property(consumed, "temperature", context)

        assert result.metadata.http.status == 200
        assert_receive {:credential_resolve, %{names: ["nosec"]}, %Wotex.Form{}, ^context}

        assert_receive {:client_request, %Request{} = request, :archive_credential}
        assert Request.method(request) == "GET"
        assert Request.uri(request) == "https://thing.example/properties/temperature"
        assert Request.max_response_bytes(request) == 4_194_304
        refute inspect(request) =~ "archive_credential"
      end

      test "WBH-A03 redirects are typed once and audience rejection stays client-owned" do
        context = Context.new!(request_id: "archive-redirect")
        redirecting = consumed(:redirect)

        assert {:error,
                %Error{
                  code: :transport_request_failed,
                  details: %{cause: %{code: :http_status}}
                }} = ConsumedThing.read_property(redirecting, "temperature", context)

        assert_receive {:client_request, %Request{}, :archive_credential}
        refute_receive {:client_request, _, _}, 25

        secret = "archive-audience-secret"
        rejection = {:audience_rejected, %{credential: secret, process: self()}}
        rejecting = consumed({:reject, rejection}, credential: secret)

        assert {:error, %Error{} = error} =
                 ConsumedThing.query_action(
                   rejecting,
                   "calibrate",
                   "https://other.example/actions/1",
                   Context.new!(request_id: "archive-audience")
                 )

        assert_receive {:client_request, %Request{} = request, ^secret}
        assert Request.uri(request) == "https://other.example/actions/1"
        refute encoded(error) =~ secret
        refute encoded(request) =~ secret
      end

      test "WBH-A04 response limits admit exact bytes and reject one over" do
        context = Context.new!(request_id: "archive-limit-exact")

        assert {:ok, %Result{payload: nil}} =
                 :exact
                 |> consumed(mode: {:body, "null"}, max_response_bytes: 4)
                 |> ConsumedThing.read_property("temperature", context)

        assert_receive {:client_request, %Request{}, :archive_credential}

        assert {:error,
                %Error{
                  code: :transport_request_failed,
                  details: %{cause: %{code: :response_body_too_large}}
                }} =
                 :over
                 |> consumed(mode: {:body, "false"}, max_response_bytes: 4)
                 |> ConsumedThing.read_property(
                   "temperature",
                   Context.new!(request_id: "archive-limit-over")
                 )

        assert_receive {:client_request, %Request{}, :archive_credential}
      end

      test "WBH-A05 Runtime supervision opens, delivers, rejects, and closes SSE" do
        {supervisor, subscription} = start_observation("22", 4, :archive_stream_ok)

        assert_receive {:client_subscribe, %Request{} = request, :archive_credential,
                        ^subscription}
        assert Request.stream?(request)
        assert Request.max_event_bytes(request) == 4

        assert_receive {:wotex_runtime, :archive_stream_ok,
                        {:ok, 22,
                         %{
                           event: "temperature",
                           id: "archive-event",
                           operation: :observeproperty
                         }}}

        assert :ok = Subscription.stop(subscription)
        assert_receive {:client_close, {:archive_stream, _}}
        refute Process.alive?(subscription)
        Supervisor.stop(supervisor)

        {over_supervisor, over_subscription} =
          start_observation("false", 4, :archive_stream_over)

        assert_receive {:client_subscribe, %Request{}, :archive_credential, ^over_subscription}

        assert_receive {:wotex_runtime, :archive_stream_over,
                        {:error,
                         %Error{
                           code: :undecodable_frame,
                           details: %{cause: %{code: :sse_event_too_large}}
                         }}}

        assert :ok = Subscription.stop(over_subscription)
        assert_receive {:client_close, {:archive_stream, _}}
        Supervisor.stop(over_supervisor)
      end

      test "WBH-A06 returned and raised client failures are redacted through Runtime" do
        secret = "archive-nested-client-secret"
        nested = {:outer, [%{credential: secret}, {:connection, self(), make_ref()}]}

        for mode <- [{:reject, nested}, {:raise, secret}] do
          assert {:error, %Error{} = error} =
                   mode
                   |> consumed()
                   |> ConsumedThing.read_property(
                     "temperature",
                     Context.new!(request_id: "archive-redaction")
                   )

          refute encoded(error) =~ secret
          assert_receive {:client_request, %Request{}, :archive_credential}
        end
      end

      defp start_observation(data, max_event_bytes, id) do
        consumed = consumed(:stream, event: data, max_event_bytes: max_event_bytes)
        context = Context.new!(request_id: "archive-subscription")

        assert {:ok, child_spec} =
                 ConsumedThing.observation_child_spec(consumed, "temperature", context,
                   id: id,
                   receiver: self(),
                   restart: :temporary
                 )

        assert {:ok, supervisor} = Supervisor.start_link([child_spec], strategy: :one_for_one)

        [{^id, subscription, :worker, [Wotex.Runtime.Subscription]}] =
          Supervisor.which_children(supervisor)

        {supervisor, subscription}
      end

      defp consumed(mode, opts \\ [])

      defp consumed(label, opts) when label in [:exact, :over] do
        consumed(Keyword.fetch!(opts, :mode), Keyword.delete(opts, :mode))
      end

      defp consumed(mode, opts) do
        {:ok, profile} = HTTP.profile()

        client_config = %{
          observer: self(),
          mode: mode,
          event: Keyword.get(opts, :event, "null")
        }

        config_options =
          [client: {Client, client_config}]
          |> maybe_put(opts, :max_response_bytes)
          |> maybe_put(opts, :max_event_bytes)

        {:ok, config} = HTTP.config(config_options)

        credentials =
          {Credentials,
           %{
             observer: self(),
             credential: Keyword.get(opts, :credential, :archive_credential)
           }}

        {:ok, value} =
          ConsumedThing.new(thing_description(),
            profiles: [profile],
            transports: %{http: HTTP.transport(config)},
            credentials: credentials
          )

        value
      end

      defp maybe_put(target, source, key) do
        if Keyword.has_key?(source, key), do: Keyword.put(target, key, source[key]), else: target
      end

      defp thing_description do
        {:ok, td} =
          Wotex.ThingDescription.from_map(%{
            "@context" => Wotex.td_context_1_1(),
            "id" => "urn:example:archive-consumer",
            "title" => "Archive consumer",
            "base" => "https://thing.example/",
            "securityDefinitions" => %{"nosec" => %{"scheme" => "nosec"}},
            "security" => ["nosec"],
            "properties" => %{
              "temperature" => %{
                "type" => "number",
                "observable" => true,
                "forms" => [
                  %{
                    "href" => "properties/temperature",
                    "contentType" => "application/json",
                    "op" => "readproperty"
                  },
                  %{
                    "href" => "properties/temperature",
                    "contentType" => "application/json",
                    "subprotocol" => "sse",
                    "op" => "observeproperty"
                  },
                  %{
                    "href" => "properties/temperature",
                    "contentType" => "application/json",
                    "subprotocol" => "sse",
                    "op" => "unobserveproperty"
                  }
                ]
              }
            },
            "actions" => %{
              "calibrate" => %{
                "forms" => [
                  %{
                    "href" => "actions/calibrate",
                    "contentType" => "application/json",
                    "op" => "queryaction"
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
    IO.puts("archive/reference vectors: WBH-A01..WBH-A06")
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

    unless status == 0 do
      violation("#{command} #{Enum.join(arguments, " ")} failed")
    end
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

WotexBindingHTTP.Check.Archive.main()
