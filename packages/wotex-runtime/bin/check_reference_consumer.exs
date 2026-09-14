defmodule Wotex.Runtime.Check.ReferenceConsumer do
  @moduledoc false

  @consumer_test ~S"""
  defmodule RuntimeArchiveConsumer.Credentials do
    @behaviour Wotex.Runtime.Credentials

    @impl true
    def resolve(_security, _form, context, %{test_pid: test_pid}) do
      send(test_pid, {:credentials, context.request_id})
      {:ok, :archive_credential}
    end
  end

  defmodule RuntimeArchiveConsumer.Transport do
    @behaviour Wotex.Runtime.Transport

    alias Wotex.Runtime.Result

    @impl true
    def request(request, execution_context, %{test_pid: test_pid}) do
      send(test_pid, {:request, request.operation, request.input, execution_context.credential})
      Result.new(request.request_id, request.operation, request.input)
    end

    @impl true
    def subscribe(request, receiver, execution_context, %{test_pid: test_pid}) do
      send(test_pid, {:subscribe, request.operation, receiver, execution_context.credential})
      {:ok, {request.operation, receiver, make_ref()}}
    end

    @impl true
    def unsubscribe(handle, request, execution_context, %{test_pid: test_pid}) do
      send(test_pid, {:unsubscribe, handle, request.operation, execution_context.credential})
      :ok
    end
  end

  defmodule RuntimeArchiveConsumerTest do
    use ExUnit.Case, async: false

    alias RuntimeArchiveConsumer.{Credentials, Transport}

    alias Wotex.Runtime.{
      BindingProfile,
      ConsumedThing,
      Context,
      Error,
      Result,
      Subscription
    }

    test "the archive is passive and short operations use explicit ports" do
      assert Application.load(:wotex_runtime) in [:ok, {:error, {:already_loaded, :wotex_runtime}}]
      assert Application.spec(:wotex_runtime, :mod) in [nil, [], :undefined]

      source_root = System.fetch_env!("WOTEX_RUNTIME_SOURCE_ROOT")
      beam = Wotex.Runtime |> :code.which() |> List.to_string()
      assert String.contains?(beam, "/consumer/_build/")
      refute String.contains?(beam, source_root <> "/")

      consumed = consumed(self())
      context = Context.new!(request_id: "archive-request")

      assert {:ok, %Result{payload: %{"temperature" => 21}}} =
               ConsumedThing.write_all_properties(
                 consumed,
                 %{"temperature" => 21},
                 context
               )

      assert_receive {:credentials, "archive-request"}
      assert_receive {:request, :writeallproperties, %{"temperature" => 21}, :archive_credential}
    end

    test "aggregate invalid and unsupported cells fail before a port call" do
      context = Context.new!(request_id: "archive-negative")
      consumed = consumed(self())

      assert {:error, %Error{code: :invalid_property_names}} =
               ConsumedThing.read_multiple_properties(consumed, [], context)

      assert {:error, %Error{code: :invalid_property_map}} =
               ConsumedThing.write_multiple_properties(consumed, %{}, context)

      limited = consumed(self(), [:readproperty])

      assert {:error, %Error{code: :compatible_form_not_found}} =
               ConsumedThing.read_all_properties(limited, context)

      refute_received {:request, _, _, _}
    end

    test "constructing subscription specifications starts no process" do
      consumed = consumed(self())
      context = Context.new!(request_id: "archive-inert")

      assert {:ok, %{id: :observation}} =
               ConsumedThing.observation_child_spec(consumed, "temperature", context,
                 id: :observation,
                 receiver: self()
               )

      assert {:ok, %{id: :event}} =
               ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
                 id: :event,
                 receiver: self()
               )

      refute_received {:subscribe, _, _, _}
    end

    test "one supervised subscription delivers and closes within its child contract" do
      consumed = consumed(self())
      context = Context.new!(request_id: "archive-one")

      assert {:ok, %{shutdown: 75} = spec} =
               ConsumedThing.observation_child_spec(consumed, "temperature", context,
                 id: :one,
                 receiver: self(),
                 restart: :temporary,
                 shutdown: 75
               )

      assert {:error, %Error{code: :invalid_shutdown_budget}} =
               ConsumedThing.observation_child_spec(consumed, "temperature", context,
                 id: :invalid_shutdown,
                 receiver: self(),
                 shutdown: -1
               )

      {:ok, supervisor} = Supervisor.start_link([spec], strategy: :one_for_one)
      assert_receive {:subscribe, :observeproperty, owner, :archive_credential}

      send(owner, {:wotex_transport, {:ok, 22, %{source: :archive}}})
      assert_receive {:wotex_runtime, :one, {:ok, 22, %{source: :archive}}}

      assert :ok = Subscription.stop(owner)
      assert_receive {:unsubscribe, _, :unobserveproperty, :archive_credential}
      assert :ok = Supervisor.stop(supervisor)
    end

    test "multiple caller-named subscriptions coexist and supervisor shutdown closes both" do
      consumed = consumed(self())
      context = Context.new!(request_id: "archive-many")

      {:ok, observation} =
        ConsumedThing.observation_child_spec(consumed, "temperature", context,
          id: :many_observation,
          receiver: self(),
          restart: :temporary,
          shutdown: 100
        )

      {:ok, event} =
        ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
          id: :many_event,
          receiver: self(),
          restart: :temporary,
          shutdown: 100
        )

      {:ok, supervisor} = Supervisor.start_link([observation, event], strategy: :one_for_one)

      owners =
        for _ <- 1..2, into: %{} do
          assert_receive {:subscribe, operation, owner, :archive_credential}
          {operation, owner}
        end

      send(owners.observeproperty, {:wotex_transport, {:ok, 23, %{}}})
      send(owners.subscribeevent, {:wotex_transport, {:ok, "alarm", %{}}})

      assert_receive {:wotex_runtime, :many_observation, {:ok, 23, %{}}}
      assert_receive {:wotex_runtime, :many_event, {:ok, "alarm", %{}}}

      assert :ok = Supervisor.stop(supervisor)
      assert_receive {:unsubscribe, _, :unobserveproperty, :archive_credential}
      assert_receive {:unsubscribe, _, :unsubscribeevent, :archive_credential}
    end

    defp consumed(test_pid, operations \\ Wotex.Runtime.operations()) do
      {:ok, profile} =
        BindingProfile.new(
          id: :archive,
          schemes: ["https"],
          operations: operations,
          media_types: ["application/json"]
        )

      {:ok, consumed} =
        ConsumedThing.new(thing_description(),
          profiles: [profile],
          transports: %{archive: {Transport, %{test_pid: test_pid}}},
          credentials: {Credentials, %{test_pid: test_pid}}
        )

      consumed
    end

    defp thing_description do
      {:ok, td} =
        Wotex.ThingDescription.from_map(%{
          "@context" => Wotex.td_context_1_1(),
          "id" => "urn:example:archive-consumer",
          "title" => "Archive Consumer",
          "base" => "https://example.test/things/archive/",
          "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
          "security" => ["nosec_sc"],
          "forms" => [
            %{
              "href" => "interactions",
              "contentType" => "application/json",
              "op" => Enum.map(Wotex.Runtime.thing_operations(), &Atom.to_string/1)
            }
          ],
          "properties" => %{
            "temperature" => %{
              "type" => "number",
              "observable" => true,
              "forms" => [
                %{
                  "href" => "properties/temperature",
                  "contentType" => "application/json",
                  "op" => [
                    "readproperty",
                    "writeproperty",
                    "observeproperty",
                    "unobserveproperty"
                  ]
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
                  "op" => ["invokeaction", "queryaction", "cancelaction"]
                }
              ]
            }
          },
          "events" => %{
            "alarm" => %{
              "forms" => [
                %{
                  "href" => "events/alarm",
                  "contentType" => "application/json",
                  "op" => ["subscribeevent", "unsubscribeevent"]
                }
              ]
            }
          }
        })

      td
    end
  end
  """

  @spec main() :: :ok
  def main do
    source_root = File.cwd!()
    core_archive = System.get_env("WOTEX_CORE_ARCHIVE")
    package_root = Path.join(System.tmp_dir!(), "wotex-runtime-reference.#{unique()}")

    result =
      try do
        verify(source_root, core_archive, package_root)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        File.rm_rf!(package_root)
      end

    report(result)
  end

  defp verify(_source_root, nil, _package_root) do
    violation("WOTEX_CORE_ARCHIVE must name the exact wotex archive")
  end

  defp verify(source_root, core_archive, package_root) do
    unless File.regular?(core_archive) do
      violation("WOTEX_CORE_ARCHIVE is not a regular file")
    end

    runtime_archive = Path.join(package_root, "wotex_runtime-0.1.0.tar")
    runtime_unpacked = Path.join(package_root, "runtime")
    core_unpacked = Path.join(package_root, "core")
    consumer = Path.join(package_root, "consumer")

    File.mkdir_p!(package_root)
    run!("mix", ["hex.build", "--output", runtime_archive], source_root)
    unpack!(runtime_archive, runtime_unpacked)
    unpack!(core_archive, core_unpacked)
    write_consumer!(consumer, runtime_unpacked, core_unpacked)

    environment = [
      {"MIX_ENV", "test"},
      {"WOTEX_RUNTIME_SOURCE_ROOT", source_root}
    ]

    run!("mix", ["deps.get"], consumer, environment)
    run!("mix", ["deps.get", "--check-locked"], consumer, environment)
    run!("mix", ["test", "--warnings-as-errors"], consumer, environment)

    IO.puts("runtime archive sha256: #{digest(runtime_archive)}")
    IO.puts("core archive sha256: #{digest(core_archive)}")
    IO.puts("reference consumer lock sha256: #{digest(Path.join(consumer, "mix.lock"))}")
    IO.puts("exact-archive reference consumer exercised requests and subscription ownership")

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
      defmodule RuntimeArchiveConsumer.MixProject do
        use Mix.Project

        def project do
          [
            app: :runtime_archive_consumer,
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

    File.write!(Path.join(test_root, "archive_consumer_test.exs"), @consumer_test)
    File.write!(Path.join(test_root, "test_helper.exs"), "ExUnit.start()\n")
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

Wotex.Runtime.Check.ReferenceConsumer.main()
