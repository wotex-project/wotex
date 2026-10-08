defmodule Wotex.Runtime.CodecBeamTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Runtime.{Codec, Context}
  alias Wotex.Runtime.Codec.Beam
  alias Wotex.Runtime.Implementation.{Admission, Error, Plan, Policy}
  alias Wotex.Runtime.TestSupport.CodecDecoder, as: Decoder
  alias Wotex.Runtime.TestSupport.ImplementationFactory, as: F

  test "consumer-supervised tasks are deterministic and retain separate instance identities" do
    p1 = F.plan(%{"suffix" => "-config"})
    p2 = next_plan(p1)
    c1 = config(p1)
    c2 = config(p2)
    assert {:ok, r1} = decode(p1, "value", %{"suffix" => "-meta"}, c1)
    assert r1.value == %{"type" => "text", "value" => "value-meta-config"}
    assert {:ok, ^r1} = decode(p1, "value", %{"suffix" => "-meta"}, c1)
    assert {:ok, r2} = decode(p2, "value", %{"suffix" => "-meta"}, c2)
    assert r1.value == r2.value and r1.instance_key != r2.instance_key
    assert Task.Supervisor.children(c1.task_supervisor) == []
    assert Task.Supervisor.children(c2.task_supervisor) == []
  end

  test "admission, contract and clock refusals leave the supervisor empty" do
    plan = F.plan()
    c = config(plan)
    d = plan.admission.descriptor
    inputs = F.inputs(d)
    {:ok, policy} = Policy.new(Map.put(inputs.policy.value, "revision", "policy.2"))

    for changed <- [
          %{c | contract: %{}},
          %{c | current_inputs: fn -> %{inputs | policy: policy} end},
          %{c | now: fn -> :foreign end},
          %{c | decoder: "foreign"},
          Map.put(c, :extra, "secret-canary")
        ] do
      assert {:error, %Error{} = error} = decode(plan, "value", %{}, changed)
      refute inspect(error) =~ "secret-canary"
      assert Task.Supervisor.children(c.task_supervisor) == []
    end

    now = System.monotonic_time(:millisecond)
    ctx = Context.new!(request_id: "request", deadline: now)

    assert {:error, %Error{code: :deadline_exceeded}} =
             Codec.decode(plan, "value", %{}, ctx, {Beam, %{c | now: fn -> now end}})

    ctx = Context.new!(request_id: "request", deadline: DateTime.utc_now())

    assert {:error, %Error{code: :enforcement_unavailable}} =
             Codec.decode(plan, "value", %{}, ctx, {Beam, c})

    assert {:error, %Error{}} = Beam.decode(<<>>, %{}, nil, c)
    assert {:error, %Error{}} = Beam.decode(<<>>, %{}, call(plan), nil)
  end

  test "deadline kills and reaps a hung task, and rejects output or refusal at equality" do
    plan = bounded_plan(30)
    c = config(plan)
    assert {:error, %Error{code: :deadline_exceeded}} = decode(plan, "hang", %{}, c)
    assert Task.Supervisor.children(c.task_supervisor) == []
    assert {:ok, _} = decode(plan, "value", %{}, c)

    for input <- ["value", "refusal"] do
      counter = :atomics.new(1, [])
      changing = %{c | now: fn -> if :atomics.add_get(counter, 1, 1) == 1, do: 100, else: 130 end}
      ctx = Context.new!(request_id: "request", deadline: 130)

      assert {:error, %Error{code: :deadline_exceeded}} =
               Codec.decode(plan, input, %{}, ctx, {Beam, changing})
    end

    counter = :atomics.new(1, [])
    backwards = %{c | now: fn -> if :atomics.add_get(counter, 1, 1) == 1, do: 100, else: 99 end}
    assert {:error, %Error{code: :deadline_exceeded}} = decode(plan, "value", %{}, backwards)
  end

  test "one active task admits no queue and owner death releases custody" do
    plan = F.plan()
    c = config(plan)
    parent = self()
    caller = spawn(fn -> send(parent, {:first, decode(plan, "hang", %{}, c)}) end)
    worker = await_worker(c.task_supervisor)
    monitor = Process.monitor(worker)
    assert {:error, %Error{code: :overloaded}} = decode(plan, "value", %{}, c)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
    assert Task.Supervisor.children(c.task_supervisor) == []
    refute_receive {:first, _}
    assert {:ok, _} = decode(plan, "value", %{}, c)
  end

  test "current policy is checked again at reply admission and decoder failures redact diagnostics" do
    plan = F.plan()
    c = config(plan)
    inputs = F.inputs(plan.admission.descriptor)
    {:ok, policy} = Policy.new(Map.put(inputs.policy.value, "revision", "policy.2"))
    counter = :atomics.new(1, [])

    changed = %{
      c
      | current_inputs: fn ->
          if :atomics.add_get(counter, 1, 1) == 1, do: inputs, else: %{inputs | policy: policy}
        end
    }

    assert {:error, %Error{code: :stale_admission}} = decode(plan, "value", %{}, changed)

    for input <- ["raise", "exit", "throw"] do
      assert {:error, %Error{code: :codec_unavailable} = error} = decode(plan, input, %{}, c)
      refute inspect(error) =~ "secret-canary"
    end

    for input <- ["malformed", "bad-return", "unknown-refusal"] do
      assert {:error, %Error{code: :protocol_fault}} = decode(plan, input, %{}, c)
    end

    assert {:error, %Error{code: :unsupported_format}} = decode(plan, "refusal", %{}, c)
    assert Task.Supervisor.children(c.task_supervisor) == []

    assert {:error, %Error{code: :codec_unavailable}} =
             decode(plan, "value", %{}, %{c | current_inputs: fn -> raise "secret-canary" end})
  end

  test "custodian loss terminates a blocked worker without exposing input in logs" do
    plan = F.plan(%{"suffix" => "configuration-canary"})
    c = config(plan)
    caller = spawn(fn -> decode(plan, "hang", %{"suffix" => "metadata-canary"}, c) end)
    worker = await_worker(c.task_supervisor)
    {:links, links} = Process.info(worker, :links)
    [custodian] = Enum.reject(links, &(&1 == c.task_supervisor))
    monitor = Process.monitor(worker)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        Process.exit(custodian, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
      end)

    refute log =~ "canary"
    assert Task.Supervisor.children(c.task_supervisor) == []
    Process.exit(caller, :kill)
  end

  defp config(plan) do
    sup = start_supervised!({Task.Supervisor, max_children: 1}, id: make_ref())

    %{
      decoder: Decoder,
      contract: plan.admission.registration.value["codec_contract"],
      task_supervisor: sup,
      current_inputs: fn -> F.inputs(plan.admission.descriptor) end,
      now: fn -> System.monotonic_time(:millisecond) end
    }
  end

  defp decode(plan, input, metadata, config) do
    Codec.decode(plan, input, metadata, Context.new!(request_id: "request"), {Beam, config})
  end

  defp call(plan) do
    {:ok, call} = Wotex.Runtime.Codec.Call.new(plan, Context.new!(request_id: "request"))
    call
  end

  defp next_plan(plan) do
    {:ok, next} = Plan.new(plan.admission, plan.configuration, F.key(2), fn _, _ -> :ok end)
    next
  end

  defp bounded_plan(milliseconds) do
    d = F.descriptor(put_in(F.descriptor_map(), ["limits", "request_ms"], milliseconds))
    {:ok, admission} = Admission.new(d, F.inputs(d))
    {:ok, plan} = Plan.new(admission, %{}, F.key(), fn _, _ -> :ok end)
    plan
  end

  defp await_worker(sup, attempts \\ 100)
  defp await_worker(_, 0), do: flunk("decoder task did not start")

  defp await_worker(sup, attempts) do
    case Task.Supervisor.children(sup) do
      [pid] ->
        pid

      [] ->
        Process.sleep(5)
        await_worker(sup, attempts - 1)
    end
  end
end
