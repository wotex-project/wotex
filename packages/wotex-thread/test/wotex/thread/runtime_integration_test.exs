defmodule Wotex.Thread.RuntimeIntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.{Form, ThingDescription, Thread}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Result}

  alias Wotex.Thread.{
    Error,
    Mapping,
    RuntimeClient,
    RuntimeErrorPort,
    RuntimeRecordingTransport,
    Transport
  }

  @corpus Path.expand("../../../priv/fixtures/wotex-integration-v1.json", __DIR__)
  @external_resource @corpus
  @vector @corpus
          |> File.read!()
          |> Jason.decode!()
          |> Map.fetch!("cases")
          |> Enum.find(&(&1["id"] == "WTH-I-F01"))

  test "WTH-I02 WTH-I03 WTH-I06 WTH-I-F01 public Runtime executes the exact corpus read" do
    input = @vector["input"]
    assert input["profile_mode"] == "daemon"
    assert input["transport_options"]["client"] == "scripted_client"
    assert input["peer_reply"]["kind"] == "client_return"

    {:ok, consumed} =
      consumer(input["thing_description"],
        target: input["transport_options"]["target"],
        timeout: input["transport_options"]["timeout"],
        peer_reply: input["peer_reply"]["value"]
      )

    origin = System.monotonic_time(:millisecond)
    deadline = origin + input["clock"]["deadline"] - input["clock"]["start"]
    context = Context.new!(request_id: input["request_id"], deadline: deadline)
    assert {:ok, result} = ConsumedThing.read_property(consumed, input["affordance"], context)
    assert_receive {:selected_request, request}
    assert [{:open, open_budget}, {:request, command, request_budget}, {:close}] = client_trace()
    assert open_budget > 0 and open_budget <= 1000
    assert request_budget > 0 and request_budget <= open_budget

    actual = %{
      "profile_id" => Atom.to_string(BindingProfile.id(request.profile)),
      "resolved_href" => request.resolved_href,
      "command" => %{"type" => Atom.to_string(command.type)},
      "result" => %{
        "request_id" => result.request_id,
        "operation" => Atom.to_string(result.operation),
        "status" => Atom.to_string(result.status),
        "payload" => result.payload,
        "metadata" => result.metadata
      },
      "extension" => Form.to_map(request.form)["example:extension"],
      "request_count" => 1,
      "owned_resources_after" => 0
    }

    assert actual == @vector["expectation"]["value"]
  end

  test "WTH-I06 every corpus case has an executing owner and exact comparison" do
    corpus = Jason.decode!(File.read!(@corpus))

    assert Map.take(corpus, ["format", "version", "status"]) == %{
             "format" => "wotex.protocol.integration",
             "version" => "1.0.0",
             "status" => "executed"
           }

    ids = Enum.map(corpus["cases"], & &1["id"])
    assert ids == Enum.uniq(ids)

    owners = %{
      "runtime_read" => "test/wotex/thread/runtime_integration_test.exs",
      "error_retry_projection" => "test/wotex/thread/runtime_error_test.exs"
    }

    for fixture <- corpus["cases"] do
      assert owner = owners[fixture["operation"]], "#{fixture["id"]} has an unknown operation"
      assert fixture["expectation"]["operator"] == "exact"
      source = File.read!(Path.expand("../../../" <> owner, __DIR__))

      assert String.contains?(source, fixture["operation"]) or
               String.contains?(source, fixture["id"])

      assert String.contains?(source, ~s(["expectation"]["value"]))
    end
  end

  test "WTH-I02 daemon profile is inert and unsupported modes remain explicit" do
    assert {:ok, profile} = Thread.profile(:daemon)
    assert profile == Thread.profile()
    assert BindingProfile.id(profile) == :thread
    assert profile.schemes == MapSet.new(["thread+unix"])
    assert profile.operations == MapSet.new([:readproperty])
    assert profile.media_types == MapSet.new()

    for mode <- [nil, :native, :sdk, "daemon", %{}] do
      assert {:error, %Error{code: :unsupported_profile, class: :permanent}} =
               Thread.profile(mode)
    end
  end

  test "WTH-I02 WTH-I03 contextual defaults choose the first compatible Form and preserve extensions" do
    map =
      td(%{
        "href" => "state",
        "example:extension" => %{"nested" => [false, 0, nil]}
      })
      |> Map.put("base", "thread+unix://controller-a/")
      |> put_in(["properties", "reading", "readOnly"], true)
      |> update_in(
        ["properties", "reading", "forms"],
        &[%{"href" => "https://example.invalid/state"} | &1]
      )

    {:ok, consumed} = consumer(map)
    assert {:ok, %Result{payload: "disabled"}} = read(consumed)
    assert_receive {:selected_request, request}
    assert request.resolved_href == "thread+unix://controller-a/state"
    assert request.affordance_type == :property
    assert Form.to_map(request.form)["example:extension"] == %{"nested" => [false, 0, nil]}
    refute Map.has_key?(Form.to_map(request.form), "contentType")
    assert_receive {:runtime_client, :open, _}
    assert_receive {:runtime_client, :request, %{type: :state}, _}
    assert_receive {:runtime_client, :close}
    assert {:error, %Error{code: :unsupported_profile}} = Thread.profile(:native)
  end

  test "WTH-I03 all four declared daemon reads retain their typed native values" do
    for {path, type, value} <- [
          {"state", :state, "leader"},
          {"version", :version, "OPENTHREAD/fixture"},
          {"network-name", :network_name, "mesh"},
          {"network-name", :network_name, nil},
          {"rloc16", :rloc16, 0},
          {"rloc16", :rloc16, nil}
        ] do
      {:ok, consumed} =
        consumer(td(%{"href" => "thread+unix://controller-a/#{path}"}), peer_reply: value)

      assert {:ok, %Result{payload: ^value, status: :ok}} = read(consumed)
      assert_receive {:selected_request, _}
      assert_receive {:runtime_client, :open, _}
      assert_receive {:runtime_client, :request, %{type: ^type}, _}
      assert_receive {:runtime_client, :close}
    end
  end

  test "WTH-I03 media, security, target and route failures acquire nothing" do
    for content_type <- ["application/json", "application/octet-stream", "text/plain"] do
      {:ok, consumed} =
        consumer(td(%{"href" => "thread+unix://controller-a/state", "contentType" => content_type}))

      assert {:error, %{details: %{cause: %{code: :unsupported_content_type}}}} = read(consumed)
      assert_receive {:selected_request, _}
      refute_received {:runtime_client, :open, _}
    end

    for {options, code} <- [
          {[target: "other"], :target_mismatch},
          {[security_mode: :authenticated], :unsupported_security},
          {[timeout: 0], :invalid_timeout}
        ] do
      {:ok, consumed} = consumer(td(), options)
      assert {:error, %{details: %{cause: %{code: ^code}}}} = read(consumed)
      assert_receive {:selected_request, _}
      refute_received {:runtime_client, :open, _}
    end

    secured = td() |> Map.put("securityDefinitions", %{"none" => %{"scheme" => "basic"}})
    {:ok, consumed} = consumer(secured)
    assert {:error, %{phase: :credentials}} = read(consumed)
    refute_received {:selected_request, _}
    refute_received {:runtime_client, :open, _}

    {:ok, consumed} = consumer(td(), credentials: :credential)
    assert {:error, %{details: %{cause: %{code: :unsupported_security}}}} = read(consumed)
    assert_receive {:selected_request, _}
    refute_received {:runtime_client, :open, _}

    for href <- [
          "thread+unix://controller-a/unknown",
          "thread+unix://user@controller-a/state",
          "thread+unix://controller-a:12/state",
          "thread+unix://controller-a/state?command=version",
          "thread+unix://controller-a/state#fragment"
        ] do
      {:ok, consumed} = consumer(td(%{"href" => href}))
      assert {:error, %{details: %{cause: %{code: :invalid_form_address}}}} = read(consumed)
      assert_receive {:selected_request, _}
      refute_received {:runtime_client, :open, _}
    end
  end

  test "WTH-I03 unknown Form terms stay data and cannot replace the path command" do
    form = %{
      "href" => "thread+unix://controller-a/state",
      "wotex:threadCommand" => "version",
      "example:nested" => %{"value" => [false, 0, nil]}
    }

    {:ok, consumed} = consumer(td(form), peer_reply: "disabled")
    assert {:ok, %Result{payload: "disabled"}} = read(consumed)
    assert_receive {:selected_request, request}
    assert Form.to_map(request.form)["wotex:threadCommand"] == "version"
    assert_receive {:runtime_client, :open, _}
    assert_receive {:runtime_client, :request, %{type: :state}, _}
    assert_receive {:runtime_client, :close}
  end

  test "WTH-I03 WTH-I06 invalid native values fail while Runtime retains falsy and null payloads" do
    for {path, reply} <- [
          {"state", :disabled},
          {"version", nil},
          {"network-name", false},
          {"rloc16", -1}
        ] do
      {:ok, consumed} =
        consumer(td(%{"href" => "thread+unix://controller-a/#{path}"}), peer_reply: reply)

      assert {:error, %{class: :protocol}} = read(consumed)
      assert_receive {:selected_request, _}
      assert_receive {:runtime_client, :open, _}
      assert_receive {:runtime_client, :request, _, _}
      assert_receive {:runtime_client, :close}
    end

    for payload <- [false, 0, <<>>, [], nil] do
      {:ok, result} =
        Result.new("runtime-read", :readproperty, payload,
          metadata: %{native_status: 0, source: "fixture"}
        )

      {:ok, consumed} = consumer(td(), result_override: result)

      assert {:ok,
              %Result{
                payload: ^payload,
                metadata: %{native_status: 0, source: "fixture"}
              }} = read(consumed)

      assert_receive {:selected_request, _}
      refute_received {:runtime_client, :open, _}
    end
  end

  test "WTH-I06 Runtime rejects mismatched result identity and operation" do
    for {id, operation} <- [{"other", :readproperty}, {"runtime-read", :writeproperty}] do
      {:ok, result} = Result.new(id, operation, "disabled")
      {:ok, consumed} = consumer(td(), result_override: result)
      assert {:error, %{code: :mismatched_transport_result}} = read(consumed)
      assert_receive {:selected_request, _}
      refute_received {:runtime_client, :open, _}
    end
  end

  test "WTH-I04 setup and exchange consume one deadline while cleanup still runs" do
    {:ok, consumed} = consumer(td(), timeout: 20, connect_delay: 30)
    assert {:error, %{class: :timeout}} = read(consumed)
    assert_receive {:selected_request, _}
    assert_receive {:runtime_client, :open, _}
    assert_receive {:runtime_client, :close}
    refute_received {:runtime_client, :request, _, _}

    {:ok, consumed} = consumer(td(), timeout: 20, request_delay: 30)
    assert {:error, %{class: :timeout}} = read(consumed)
    assert_receive {:selected_request, _}
    assert_receive {:runtime_client, :open, open_budget}
    assert_receive {:runtime_client, :request, %{type: :state}, request_budget}
    assert request_budget <= open_budget
    assert_receive {:runtime_client, :close}

    for deadline <- [DateTime.add(DateTime.utc_now(), -1), System.monotonic_time(:millisecond) - 1] do
      {:ok, consumed} = consumer(td())

      assert {:error, %{class: :timeout}} =
               read(consumed, Context.new!(request_id: "expired", deadline: deadline))

      assert_receive {:selected_request, _}
      refute_received {:runtime_client, :open, _}
    end
  end

  test "WTH-I05 daemon profile exposes no Runtime stream and starts no process" do
    {:ok, consumed} = consumer(td())

    assert {:error, %{code: :compatible_form_not_found}} =
             ConsumedThing.observation_child_spec(consumed, "reading", context(),
               id: :thread_observation,
               receiver: self(),
               max_queue_length: 1000,
               overflow: :stop,
               restart: :temporary
             )

    assert {:error, %Error{code: :not_supported}} = Transport.subscribe(nil, self(), nil, nil)
    assert {:error, %Error{code: :not_supported}} = Transport.unsubscribe(nil, nil, nil, nil)
    refute_received {:selected_request, _}
    refute_received {:runtime_client, :open, _}
  end

  test "WTH-I03 mapping rejects read input and malformed contextual Forms without I/O" do
    {:ok, form} = Form.new(%{"href" => "thread+unix://controller-a/state"}, for: :property)

    assert {:error, %Error{code: :invalid_form_address}} =
             Mapping.command(form, :readproperty, :unexpected)

    assert {:error, %Error{code: :unsupported_operation}} =
             Mapping.command(form, :writeproperty, nil)

    assert {:error, %Error{code: :invalid_form_address}} =
             Mapping.command(%Form{value: %{"href" => self()}}, :readproperty, nil)
  end

  defp client_trace(acc \\ []) do
    receive do
      {:runtime_client, :open, budget} ->
        client_trace([{:open, budget} | acc])

      {:runtime_client, :request, command, budget} ->
        client_trace([{:request, command, budget} | acc])

      {:runtime_client, :close} ->
        client_trace([{:close} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp consumer(map, options \\ []) do
    {:ok, td} = ThingDescription.from_map(map)
    {credentials, options} = Keyword.pop(options, :credentials, nil)

    config =
      Keyword.merge(
        [
          client: RuntimeClient,
          test_pid: self(),
          target: "controller-a",
          peer_reply: "disabled"
        ],
        options
      )

    ConsumedThing.new(td,
      profiles: [Thread.profile()],
      transports: %{thread: {RuntimeRecordingTransport, config}},
      credentials: {RuntimeErrorPort, credentials}
    )
  end

  defp td(form \\ %{"href" => "thread+unix://controller-a/state"}) do
    %{
      "@context" => "https://www.w3.org/2022/wot/td/v1.1",
      "title" => "Thread Runtime fixture",
      "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
      "security" => ["none"],
      "properties" => %{"reading" => %{"forms" => [form]}}
    }
  end

  defp context, do: Context.new!(request_id: "runtime-read")

  defp read(consumed, context \\ context()),
    do: ConsumedThing.read_property(consumed, "reading", context)
end
