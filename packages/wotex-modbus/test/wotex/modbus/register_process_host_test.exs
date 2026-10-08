defmodule Wotex.Modbus.RegisterProcessHostTest do
  @moduledoc false

  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Wotex.Modbus.{
    RegisterCodec,
    RegisterCodecFixture,
    RegisterProcessDriver,
    RegisterProcessFixture
  }

  alias Wotex.Modbus.RegisterCodec.Host
  alias Wotex.Runtime.{Codec, Context}
  alias Wotex.Runtime.Codec.{Call, Wire}
  alias Wotex.Runtime.Implementation.{Error, Plan}

  @configuration %{
    "registers" => 1,
    "byte_order" => "big",
    "word_order" => "big",
    "scale" => -2,
    "signed" => false
  }
  @metadata %{"format" => "packed-bcd-v1"}

  test "explicit supervision, exact handshake, fragmented output and independent generations" do
    a = fixture(mode: :fragment)
    b = fixture(configuration: Map.put(@configuration, "byte_order", "little"), generation: 2)
    assert :temporary == Host.child_spec(a.config).restart
    assert :ok == Host.await_ready(a.host)
    assert :ok == Host.await_ready(b.host)
    assert {:ok, result} = decode(a, <<0x12, 0x34>>)
    assert result.value == %{"type" => "decimal", "coefficient" => "1234", "exponent" => -2}
    assert {:ok, result} = decode(b, <<0x34, 0x12>>)
    assert result.instance_key.generation == 2
    assert result.value["coefficient"] == "1234"
    assert :ok == Host.stop(a.host)
    refute GenServer.call(a.driver, :snapshot).resources
    assert {:ok, _} = decode(b, <<0x34, 0x12>>)
    assert :ok == Host.stop(b.host)
    assert_receive {:close, _, _, 1000}
  end

  test "static inputs are closed and deployment profiles never choose an implicit driver" do
    f = fixture(start: false)

    for config <- [
          nil,
          %{},
          Map.put(f.config, :extra, true),
          %{f.config | owner: nil},
          %{f.config | now: 0},
          %{f.config | current_inputs: nil},
          %{f.config | driver: {String, %{}}}
        ] do
      assert {:error, %Error{code: :invalid_configuration}} = Host.start_link(config)
    end

    assert {:error, %Error{code: :incompatible_binding}} =
             Host.start_link(%{f.config | plan: RegisterCodecFixture.plan(@configuration)})

    {module, driver_config} = f.config.driver

    for profile <- [
          Map.put(driver_config.profile, :extra, true),
          Map.put(driver_config.profile, :pid, nil),
          Map.put(driver_config.profile, :artifact, %{}),
          Map.put(driver_config.profile, :codec_contract, %{})
        ] do
      assert {:error, %Error{code: :invalid_configuration}} =
               Host.start_link(%{f.config | driver: {module, %{driver_config | profile: profile}}})
    end

    for result <- [
          :raise,
          :throw,
          :exit,
          {:error, :enforcement_unavailable},
          {:error, "secret"},
          :bad
        ] do
      assert {:error, %Error{}} =
               Host.start_link(%{
                 f.config
                 | driver: {module, Map.put(driver_config, :returns, %{profile: result})}
               })
    end

    refute_receive {:claimed, _, _, _}
    assert {:error, %Error{code: :invalid_configuration}} = Host.await_ready(nil)
    assert {:error, %Error{code: :invalid_configuration}} = Host.decode(<<>>, %{}, nil, nil)
    assert {:error, %Error{code: :codec_unavailable}} = Host.stop(spawn(fn -> :ok end))
  end

  test "current admission and every enforcement guarantee are required before open" do
    for opts <- [[guarantees: ~w(immutable_deployment)], []] do
      f = fixture(start: false, plan_options: opts)
      if opts == [], do: Agent.update(f.current, &%{&1 | inputs: nil})
      {:ok, host} = Host.start_link(f.config)
      ref = Process.monitor(host)
      assert_receive {:DOWN, ^ref, :process, ^host, :normal}
      refute GenServer.call(f.driver, :snapshot).resources
      refute_receive {:claimed, _, ^host, _}
    end
  end

  test "startup waiter bounds, early output, mismatched and duplicate ready retire the generation" do
    f = fixture(mode: :hold_open)
    assert_receive {:claimed, driver, host, _}
    assert driver == f.driver and host == f.host
    assert {:error, %Error{code: :instance_not_ready}} = decode(f, <<0x12, 0x34>>)
    waiter = Task.async(fn -> Host.await_ready(f.host) end)
    sync(f.host)
    assert {:error, %Error{code: :overloaded}} = Host.await_ready(f.host)
    emit(f, {:stdout, "{"})
    assert {:error, %Error{code: :protocol_fault}} = Task.await(waiter)

    for mode <- [:wrong_ready, :double_reply, :partial_tail] do
      f = fixture(mode: :manual_ready)
      waiter = Task.async(fn -> Host.await_ready(f.host) end)
      sync(f.host)
      GenServer.call(f.driver, {:mode, mode})
      ready = ready(f)
      bytes = encoded(if(mode == :wrong_ready, do: Map.put(ready, "generation", 2), else: ready))

      bytes =
        case mode do
          :double_reply -> bytes <> bytes
          :partial_tail -> bytes <> "{"
          _ -> bytes
        end

      emit(f, {:stdout, bytes})
      assert {:error, %Error{code: :protocol_fault}} = Task.await(waiter)
    end

    f = fixture()
    assert :ok == Host.await_ready(f.host)
    ref = Process.monitor(f.host)
    emit(f, {:stdout, encoded(ready(f))})
    assert_receive {:DOWN, ^ref, :process, _, :normal}
  end

  test "correlation faults and unsolicited tails fail before success without fallback" do
    for mode <- [:wrong_seq, :wrong_request, :double_reply, :partial_tail] do
      f = fixture()
      assert :ok == Host.await_ready(f.host)
      GenServer.call(f.driver, {:mode, mode})
      assert {:error, %Error{code: :protocol_fault}} = decode(f, <<0x12, 0x34>>)
      refute GenServer.call(f.driver, :snapshot).resources
      assert_receive {:write, _, "decode", 1}
      refute_receive {:write, _, "decode", 2}
    end
  end

  test "deterministic decoder refusals keep ready and increment sequences" do
    f = fixture()
    assert :ok == Host.await_ready(f.host)
    assert {:error, %Error{code: :invalid_input}} = decode(f, <<0xAB, 0xCD>>)

    assert {:error, %Error{code: :unsupported_format}} =
             decode(f, <<0x12, 0x34>>, %{"format" => "other"})

    assert {:ok, _} = decode(f, <<0x12, 0x34>>)
    assert_receive {:write, _, "decode", 1}
    assert_receive {:write, _, "decode", 2}
    assert_receive {:write, _, "decode", 3}
    assert :ok == Host.stop(f.host)
  end

  test "one active request, no queue, exact Plan and sequence exhaustion" do
    f = fixture(mode: :manual_decode)
    assert :ok == Host.await_ready(f.host)
    task = Task.async(fn -> decode(f, <<0x12, 0x34>>) end)
    assert_receive {:write, _, "decode", 1}
    assert {:error, %Error{code: :overloaded}} = decode(f, <<0x12, 0x34>>)
    emit(f, {:stdout, encoded(reply_frame("result", 1, %{"value" => %{"type" => "null"}}))})
    assert {:ok, _} = Task.await(task)

    {:ok, newer} =
      Call.new(
        RegisterProcessFixture.plan(@configuration, generation: 2),
        Context.new!(request_id: "request")
      )

    assert {:error, %Error{code: :stale_generation}} = Host.decode(<<>>, @metadata, newer, f.host)

    {:ok, other} =
      Plan.new(
        f.config.plan.admission,
        Map.put(@configuration, "scale", 0),
        f.config.plan.instance_key,
        &RegisterCodec.validate_configuration/2
      )

    {:ok, other} = Call.new(other, Context.new!(request_id: "request"))
    assert {:error, %Error{code: :correlation_failed}} = Host.decode(<<>>, @metadata, other, f.host)

    assert {:error, %Error{code: :invalid_configuration}} =
             Host.decode(<<>>, @metadata, nil, f.host)

    assert {:error, %Error{code: :invalid_input}} = decode(f, String.duplicate("x", 65_537))
    :sys.replace_state(f.host, &%{&1 | seq: 9_007_199_254_740_992})
    assert {:error, %Error{code: :codec_unavailable}} = decode(f, <<0x12, 0x34>>)
    refute_receive {:write, _, "decode", 2}
  end

  test "deadline equality, backward clocks and current admission refuse late results" do
    for change <- [:deadline, :backwards, :admission] do
      f = fixture(mode: :manual_decode, deadline: 200)
      assert :ok == Host.await_ready(f.host)
      task = Task.async(fn -> decode(f, <<0x12, 0x34>>) end)
      assert_receive {:write, _, "decode", 1}

      case change do
        :deadline -> Agent.update(f.current, &%{&1 | now: 200})
        :backwards -> Agent.update(f.current, &%{&1 | now: 99})
        :admission -> Agent.update(f.current, &%{&1 | inputs: nil})
      end

      emit(f, {:stdout, encoded(reply_frame("result", 1, %{"value" => %{"type" => "null"}}))})
      assert {:error, %Error{code: code}} = Task.await(task)
      assert code in [:deadline_exceeded, :invalid_admission_inputs]
    end

    f = fixture(mode: :manual_decode, plan_options: [limits: %{"request_ms" => 20}])
    assert :ok == Host.await_ready(f.host)
    assert {:error, %Error{code: :deadline_exceeded}} = decode(f, <<0x12, 0x34>>)
    refute GenServer.call(f.driver, :snapshot).resources
  end

  test "caller loss and consumer owner loss retire opened and partially opened resources" do
    f = fixture(mode: :manual_decode)
    assert :ok == Host.await_ready(f.host)
    caller = spawn(fn -> decode(f, <<0x12, 0x34>>) end)
    assert_receive {:write, _, "decode", 1}
    ref = Process.monitor(f.host)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    refute GenServer.call(f.driver, :snapshot).resources

    for mode <- [:hold_open, :normal] do
      owner =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      f = fixture(mode: mode, owner: owner)
      assert_receive {:claimed, _, _, _}
      if mode == :normal, do: assert(:ok == Host.await_ready(f.host))
      ref = Process.monitor(f.host)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^ref, :process, _, :normal}
      refute GenServer.call(f.driver, :snapshot).resources
    end
  end

  @tag capture_log: true
  test "independent scripted custody survives forced host death, driver death is unconfirmed" do
    f = fixture(mode: :hold_open)
    assert_receive {:claimed, _, _, _}
    Process.unlink(f.host)
    Process.exit(f.host, :kill)
    assert_receive {:custody_released, _}
    refute GenServer.call(f.driver, :snapshot).resources
    f = fixture(mode: :manual_decode)
    assert :ok == Host.await_ready(f.host)
    task = Task.async(fn -> decode(f, <<0x12, 0x34>>) end)
    assert_receive {:write, _, "decode", 1}
    Process.exit(f.driver, :kill)
    assert {:error, %Error{code: :cleanup_unconfirmed}} = Task.await(task)
  end

  test "stop drains once, hung or refused cleanup never reports confirmation" do
    for cleanup <- [:unconfirmed, :hang] do
      f =
        fixture(
          cleanup: cleanup,
          mode: :manual_decode,
          plan_options: [limits: %{"shutdown_ms" => 20}]
        )

      assert :ok == Host.await_ready(f.host)
      pending = Task.async(fn -> decode(f, <<0x12, 0x34>>) end)
      assert_receive {:write, _, "decode", 1}
      stop = Task.async(fn -> Host.stop(f.host) end)
      assert_receive {:close, _, _, 20}

      if cleanup == :hang do
        assert {:error, %Error{code: :instance_draining}} = decode(f, <<0x12, 0x34>>)
        assert {:error, %Error{code: :overloaded}} = Host.stop(f.host)
        emit(f, {:stdout, "discard-secret"})
      end

      assert {:error, %Error{code: :cleanup_unconfirmed}} = Task.await(pending)
      assert {:error, %Error{code: :cleanup_unconfirmed}} = Task.await(stop)
      assert_receive {:write, _, "stop", nil}
      refute_receive {:close, _, _, _}
    end
  end

  test "stderr is bounded and discarded, foreign channels never enter framing" do
    f = fixture()
    assert :ok == Host.await_ready(f.host)
    send(f.host, {:wotex_modbus_codec, make_ref(), {:stdout, String.duplicate("x", 300_000)}})
    send(f.host, :unrelated)
    emit(f, {:stdout, <<>>})
    emit(f, {:stderr, String.duplicate("x", 4096)})
    assert {:ok, _} = decode(f, <<0x12, 0x34>>)
    ref = Process.monitor(f.host)
    emit(f, {:stderr, "x"})
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    refute GenServer.call(f.driver, :snapshot).resources
  end

  test "inspection, status, callback exceptions and protocol faults expose no secret canaries" do
    log =
      capture_log(fn ->
        f = fixture(driver_secret: "configuration-secret-canary")
        assert :ok == Host.await_ready(f.host)
        refute inspect(Host.child_spec(f.config)) =~ "configuration-secret-canary"
        refute inspect(:sys.get_status(f.host)) =~ "configuration-secret-canary"
        GenServer.call(f.driver, {:mode, :manual_decode})
        task = Task.async(fn -> decode(f, "input-secret-canary") end)
        assert_receive {:write, _, "decode", 1}
        emit(f, {:stderr, "stderr-secret-canary"})
        emit(f, {:stdout, "{\"diagnostic\":\"output-secret-canary\"}\n"})
        assert {:error, %Error{code: :protocol_fault} = error} = Task.await(task)
        refute inspect(error) =~ "secret-canary"

        for result <- [:raise, :throw, :exit, {:error, "driver-secret-canary"}, :bad] do
          f = fixture(returns: %{write: result})
          ref = Process.monitor(f.host)
          assert_receive {:DOWN, ^ref, :process, _, :normal}
        end
      end)

    refute log =~ "secret-canary"
  end

  test "reference widths, byte orders, signed values and scale extrema cross the host unchanged" do
    for width <- 1..4, byte <- ~w(big little), word <- ~w(big little) do
      config =
        Map.merge(@configuration, %{
          "registers" => width,
          "byte_order" => byte,
          "word_order" => word
        })

      words =
        for <<a, b <- :binary.copy(<<0x12, 0x34>>, width)>>,
          do: if(byte == "big", do: <<a, b>>, else: <<b, a>>)

      words = if word == "big", do: words, else: Enum.reverse(words)
      input = IO.iodata_to_binary(words)
      f = fixture(configuration: config)
      assert :ok == Host.await_ready(f.host)
      assert {:ok, result} = decode(f, input)

      assert result.value == %{
               "type" => "decimal",
               "coefficient" => String.duplicate("1234", width),
               "exponent" => -2
             }

      assert :ok == Host.stop(f.host)
    end

    for scale <- [-32_768, 32_767], {sign, coefficient} <- [{12, "123"}, {13, "-123"}] do
      f = fixture(configuration: Map.merge(@configuration, %{"signed" => true, "scale" => scale}))
      assert :ok == Host.await_ready(f.host)
      assert {:ok, result} = decode(f, <<0x12, 3::4, sign::4>>)

      assert result.value == %{
               "type" => "decimal",
               "coefficient" => coefficient,
               "exponent" => scale
             }

      assert {:error, %Error{code: :unsupported_value}} = decode(f, <<0, 0x0D>>)
      assert :ok == Host.stop(f.host)
    end
  end

  test "decode dispatch validates current admission, clocks, frame ceilings and metadata" do
    for changed <- [nil, :backwards, :mismatch, :invalid_clock, :expired] do
      f = fixture(deadline: 200)
      assert :ok == Host.await_ready(f.host)

      case changed do
        nil -> Agent.update(f.current, &%{&1 | inputs: nil})
        :backwards -> Agent.update(f.current, &%{&1 | now: 99})
        :mismatch -> Agent.update(f.current, &%{&1 | now: ~U[2026-10-08 00:00:00Z]})
        :invalid_clock -> Agent.update(f.current, &%{&1 | now: :invalid})
        :expired -> Agent.update(f.current, &%{&1 | now: 200})
      end

      assert {:error, %Error{}} = decode(f, <<0x12, 0x34>>)
      assert_receive {:close, _, _, _}
      refute_receive {:write, _, "decode", _}
    end

    f = fixture(plan_options: [limits: %{"frame_bytes" => 700}])
    assert :ok == Host.await_ready(f.host)
    assert {:error, %Error{code: :invalid_input}} = decode(f, :binary.copy(<<0>>, 1000))
    assert {:ok, _} = decode(f, <<0x12, 0x34>>)

    assert {:error, %Error{code: :protocol_fault}} =
             Host.decode(<<0>>, nil, Call.new(f.config.plan, f.config.context) |> elem(1), f.host)
  end

  test "DateTime deadlines, startup expiry and unknown messages fail closed" do
    now = ~U[2026-10-08 00:00:00Z]
    f = fixture(start: false, deadline: DateTime.add(now, 1, :second))
    Agent.update(f.current, &%{&1 | now: now})
    host = start_supervised!({Host, f.config}, id: make_ref())
    assert :ok == Host.await_ready(host)
    assert {:ok, _} = decode(%{f | host: host}, <<0x12, 0x34>>)
    assert :ok == Host.stop(host)
    f = fixture(mode: :hold_open, plan_options: [limits: %{"startup_ms" => 20}])
    assert {:error, %Error{code: :deadline_exceeded}} = Host.await_ready(f.host)

    for event <- [:opened, {:stderr, nil}, {:failed, "foreign-secret"}, :exited] do
      f = fixture()
      assert :ok == Host.await_ready(f.host)
      ref = Process.monitor(f.host)
      emit(f, event)
      assert_receive {:DOWN, ^ref, :process, _, :normal}
      refute GenServer.call(f.driver, :snapshot).resources
    end
  end

  test "four fixed refusals preserve readiness and stale timers cannot retire an idle instance" do
    f = fixture(mode: :manual_decode)
    assert :ok == Host.await_ready(f.host)

    for {code, seq} <-
          Enum.with_index(~w(invalid_input unsupported_format unsupported_value output_limit), 1) do
      task = Task.async(fn -> decode(f, <<0x12, 0x34>>) end)
      assert_receive {:write, _, "decode", ^seq}
      emit(f, {:stdout, encoded(reply_frame("refusal", seq, %{"code" => code}))})
      assert {:error, %Error{} = error} = Task.await(task)
      assert Atom.to_string(error.code) == code
      assert :ok == Host.await_ready(f.host)
    end

    send(f.host, {:timeout, make_ref()})
    assert {:error, %Error{code: :invalid_input}} = GenServer.call(f.host, :unexpected)
    assert :ok == Host.stop(f.host)
  end

  test "shared driver claims and callback failures cannot clean another owner's resources" do
    f = fixture()
    assert :ok == Host.await_ready(f.host)

    {:ok, second} =
      Host.start_link(%{
        f.config
        | plan: RegisterProcessFixture.plan(@configuration, generation: 2)
      })

    ref = Process.monitor(second)
    assert_receive {:DOWN, ^ref, :process, ^second, :normal}
    assert GenServer.call(f.driver, :snapshot).resources
    assert {:ok, _} = decode(f, <<0x12, 0x34>>)
    assert :ok == Host.stop(f.host)

    for result <- [
          :raise,
          :throw,
          :exit,
          {:error, :artifact_unverified},
          {:error, :enforcement_unavailable},
          {:error, :startup_failed},
          {:error, :codec_unavailable},
          {:error, :overloaded},
          {:error, :cleanup_unconfirmed},
          {:error, "secret"},
          :bad
        ] do
      f = fixture(returns: %{open: result})
      ref = Process.monitor(f.host)
      assert_receive {:DOWN, ^ref, :process, _, :normal}
      refute GenServer.call(f.driver, :snapshot).resources
    end

    for result <- [:raise, {:error, :cleanup_unconfirmed}, :bad] do
      f = fixture(returns: %{close: result})
      assert :ok == Host.await_ready(f.host)
      assert {:error, %Error{code: :cleanup_unconfirmed}} = Host.stop(f.host)
    end
  end

  defp fixture(opts \\ []) do
    plan =
      RegisterProcessFixture.plan(
        Keyword.get(opts, :configuration, @configuration),
        Keyword.merge(Keyword.get(opts, :plan_options, []), Keyword.take(opts, [:generation]))
      )

    driver =
      start_supervised!(
        {RegisterProcessDriver,
         %{
           observer: self(),
           mode: Keyword.get(opts, :mode, :normal),
           cleanup: Keyword.get(opts, :cleanup, :confirmed_local)
         }},
        id: make_ref(),
        restart: :temporary
      )

    inputs =
      RegisterProcessFixture.inputs(plan.admission.descriptor, Keyword.get(opts, :plan_options, []))

    current = start_supervised!({Agent, fn -> %{inputs: inputs, now: 100} end}, id: make_ref())

    profile = %{
      pid: driver,
      artifact: plan.admission.descriptor.value["artifact"],
      enforcement: plan.admission.registration.value["enforcement"],
      codec_contract: RegisterCodec.contract()
    }

    context = Context.new!(request_id: "request", deadline: Keyword.get(opts, :deadline))

    config = %{
      plan: plan,
      context: context,
      driver:
        {RegisterProcessDriver,
         %{
           profile: profile,
           secret: Keyword.get(opts, :driver_secret),
           returns: Keyword.get(opts, :returns, %{})
         }},
      current_inputs: fn -> Agent.get(current, & &1.inputs) end,
      now: fn -> Agent.get(current, & &1.now) end,
      owner: Keyword.get(opts, :owner, self())
    }

    host =
      if Keyword.get(opts, :start, true),
        do: start_supervised!({Host, config}, id: make_ref()),
        else: nil

    %{config: config, current: current, driver: driver, host: host}
  end

  defp decode(f, input, metadata \\ @metadata),
    do: Codec.decode(f.config.plan, input, metadata, f.config.context, {Host, f.host})

  defp emit(f, event), do: GenServer.call(f.driver, {:emit, event})
  defp sync(host), do: sync(host, 1000)

  defp sync(host, attempts) when attempts > 0 do
    case :sys.get_state(host).ready_waiter do
      nil ->
        Process.sleep(1)
        sync(host, attempts - 1)

      _ ->
        :ok
    end
  end

  defp sync(_, 0), do: flunk("startup waiter was not registered")

  defp ready(f) do
    assert_receive {:write, driver, "hello", nil}
    assert driver == f.driver

    GenServer.call(f.driver, :snapshot).hello
    |> Map.delete("configuration")
    |> Map.put("type", "ready")
  end

  defp encoded(frame) do
    {:ok, bytes} = Wire.encode(frame)
    bytes
  end

  defp reply_frame(type, seq, values),
    do: Map.merge(%{"v" => 1, "type" => type, "seq" => seq, "request_id" => "request"}, values)
end
