# Explicit integration lane: pass the producer-owned WPF vector directory.
ExUnit.start()

defmodule Wotex.Binding.MQTT.JSONProjectionProfilesTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Binding.MQTT.{Delivery, JSONProjection}
  alias Wotex.Profiles.{Binding, Capture, Compiler, Interpreter, Projection}

  @fixtures Path.expand(hd(System.argv()))

  test "one installed MQTT projection feeds two compiled semantic channels without route inference" do
    {projection, limits} = compiled()
    assert {:ok, checked} = Projection.to_map(projection, limits)
    assert length(checked["channel_plans"]) == 2

    {:ok, delivery} =
      Delivery.new(~s({"left":25,"right":26}), topic: "measurements", qos: 2, retain: true)

    for {channel, expected} <- [{"left", "25"}, {"right", "26"}] do
      selector = %{"topic" => "measurements", "path" => [channel]}
      assert :ok = JSONProjection.validate_selector(selector)
      assert {:ok, value, %{retained: true, qos: 2}} = JSONProjection.project(delivery, selector)

      assert {:ok, proposal} =
               Interpreter.project(projection, report(projection, channel, value), limits)

      assert proposal["normalized_value"] == %{"type" => "sint", "value" => expected}
      assert proposal["channel_id"] == channel
      assert proposal["continuity"] == "retained"
      assert proposal["sequence"] == nil
      assert proposal["source_time"] == nil

      assert proposal["receipt_time"] == %{
               "epoch" => String.duplicate("f", 32),
               "monotonic_us" => "1"
             }
    end
  end

  test "raw-value schema and exact binding identity remain authoritative after payload projection" do
    {projection, limits} = compiled()
    {:ok, delivery} = Delivery.new(~s({"left":"25"}), topic: "measurements")

    assert {:ok, value, _} =
             JSONProjection.project(delivery, %{"topic" => "measurements", "path" => ["left"]})

    assert {:error, %Wotex.Profiles.Error{code: :out_of_domain}} =
             Interpreter.project(projection, report(projection, "left", value), limits)

    good = report(projection, "left", %{"type" => "sint", "value" => "25"})
    foreign = put_in(good, ["binding", "sha256"], String.duplicate("a", 64))
    assert {:error, %Wotex.Profiles.Error{}} = Interpreter.project(projection, foreign, limits)
  end

  test "compiler refuses uninstalled raw contracts and malformed structural selectors" do
    {projection, limits} = compiled()
    inputs = projection.inputs
    missing = Map.put(inputs["closure"], "contracts", [])

    assert {:error, %Wotex.Profiles.Error{code: :missing_reference}} =
             Compiler.compile(inputs["profile"], missing, inputs["capture"], limits)

    bad = put_in(inputs["profile"], ["channels", Access.at(0), "selector", "path"], [0])

    assert {:error, %Wotex.Profiles.Error{code: :unsupported_selector}} =
             Compiler.compile(bad, inputs["closure"], inputs["capture"], limits)
  end

  defp compiled do
    limits = fixture("limits")

    contract = %{
      "id" => "urn:example:decoder:mqtt-json-output",
      "version" => "1.0.0",
      "sha256" => String.duplicate("d", 64)
    }

    body =
      fixture("installed-binding")
      |> Map.delete("sha256")
      |> Map.put("id", "urn:example:binding:mqtt-json")
      |> Map.put("operations", ["observeproperty"])
      |> Map.put("selector_schema", JSONProjection.selector_schema())
      |> Map.put("raw_value_contract", contract)

    {:ok, sha} = Binding.digest(body, limits)
    binding = Map.put(body, "sha256", sha)
    {:ok, installed} = Binding.new(binding, limits)
    {:ok, reference} = Binding.reference(installed, limits)

    capture =
      fixture("capture")
      |> Map.delete("digest")
      |> Map.put("binding", reference)

    {:ok, digest} = Capture.digest(capture, installed, limits)
    capture = Map.put(capture, "digest", digest)
    profile = fixture("compiler-profile") |> Map.put("binding", reference)
    base = hd(profile["channels"])

    channels =
      for name <- ["left", "right"] do
        base
        |> Map.put("id", name)
        |> Map.put("affordance", %{"kind" => "property", "name" => name})
        |> Map.put("operations", ["observeproperty"])
        |> Map.put("selector", %{"topic" => "measurements", "path" => [name]})
      end

    profile = Map.put(profile, "channels", channels)

    closure = %{
      "definitions" => [fixture("industrial-definition")],
      "bindings" => [binding],
      "contracts" => [contract]
    }

    {:ok, projection} = Compiler.compile(profile, closure, capture, limits)
    {projection, limits}
  end

  defp report(projection, channel, value) do
    %{
      "channel_id" => channel,
      "profile_sha256" => projection.data["profile_sha256"],
      "binding" => projection.data["binding"],
      "capture_epoch" => projection.data["capture_epoch"],
      "source_ref" => "synthetic-source",
      "source_epoch" => String.duplicate("e", 32),
      "sequence" => nil,
      "source_time" => nil,
      "receipt_time" => %{"epoch" => String.duplicate("f", 32), "monotonic_us" => "1"},
      "continuity" => "retained",
      "quality" => "usable",
      "quality_reason" => nil,
      "value" => value
    }
  end

  defp fixture(name) do
    @fixtures
    |> Path.join(name <> ".json")
    |> File.read!()
    |> Jason.decode!()
  end
end
