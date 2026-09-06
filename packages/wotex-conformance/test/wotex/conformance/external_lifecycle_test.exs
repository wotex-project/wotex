defmodule Wotex.Conformance.ExternalLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Conformance.{Error, TestFixtures}
  alias Wotex.Conformance.Target.External

  setup do
    {root, archive, _} = TestFixtures.subject_archive!()
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, archive: archive}
  end

  test "a target that does not read stdin returns within the invocation budget", context do
    target =
      TestFixtures.external_target!(context.archive, "sleep", sleep_ms: 5_000, timeout_ms: 50)

    request = %{
      "vector" => %{"id" => "td11.parse.minimal"},
      "input" => String.duplicate("x", 1_000_000)
    }

    invocation =
      Task.async(fn ->
        result = External.invoke(target, request)
        {:links, links} = Process.info(self(), :links)
        {result, Enum.filter(links, &is_port/1)}
      end)

    completed = Task.yield(invocation, 2_000) || Task.shutdown(invocation, :brutal_kill)
    assert {:ok, {{:error, %Error{code: :target_timeout}, duration}, []}} = completed
    assert duration < 2_000_000
  end

  test "invalid request identity starts no target", context do
    marker = Path.join(context.root, "invoked")
    target = TestFixtures.external_target!(context.archive, "pass", marker_path: marker)

    assert {:error, %Error{code: :invalid_target_request}, _} = External.invoke(target, %{})
    refute File.exists?(marker)
  end

  test "completed and failed exchanges leave no owned port", context do
    request = %{"vector" => %{"id" => "td11.parse.minimal"}}
    {:links, before_links} = Process.info(self(), :links)
    before_ports = Enum.filter(before_links, &is_port/1)

    for {mode, code} <- [
          {"malformed", :invalid_target_json},
          {"wrong_vector", :target_vector_mismatch},
          {"nonzero", :target_exit_nonzero}
        ] do
      target = TestFixtures.external_target!(context.archive, mode)
      assert {:error, %Error{code: ^code}, _} = External.invoke(target, request)
      {:links, after_links} = Process.info(self(), :links)
      assert Enum.filter(after_links, &is_port/1) == before_ports
    end

    target = TestFixtures.external_target!(context.archive, "pass")
    assert {:ok, response, _} = External.invoke(target, request)
    assert response.vector_id == "td11.parse.minimal"
    {:links, after_links} = Process.info(self(), :links)
    assert Enum.filter(after_links, &is_port/1) == before_ports
  end
end
