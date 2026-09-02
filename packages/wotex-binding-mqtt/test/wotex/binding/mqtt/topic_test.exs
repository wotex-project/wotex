defmodule Wotex.Binding.MQTT.TopicTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT.{Error, Topic}

  test "accepts MQTT Topic Names without normalization" do
    for name <- ["things/value", "/", "/leading", "trailing/", "with space"] do
      assert :ok = Topic.validate_name(name)
    end
  end

  test "rejects invalid Topic Names" do
    for {name, code} <- [
          {nil, :invalid_topic_name},
          {"", :invalid_topic_name},
          {"things/+", :topic_name_contains_wildcard},
          {"things/#", :topic_name_contains_wildcard},
          {"bad\0name", :invalid_topic_name},
          {<<255>>, :invalid_topic_name},
          {String.duplicate("a", 65_536), :invalid_topic_name}
        ] do
      assert {:error, %Error{code: ^code}} = Topic.validate_name(name)
    end
  end

  test "accepts valid Topic Filters and shared subscription syntax" do
    for filter <- [
          "things/value",
          "things/+",
          "things/+/value",
          "things/#",
          "#",
          "+",
          "/+/",
          "$share/readers/things/+/value"
        ] do
      assert :ok = Topic.validate_filter(filter)
    end
  end

  test "rejects malformed Topic Filter wildcards and shared syntax" do
    for {filter, code} <- [
          {"", :invalid_topic_filter},
          {nil, :invalid_topic_filter},
          {"things/#/value", :invalid_topic_filter_wildcard},
          {"things/value#", :invalid_topic_filter_wildcard},
          {"things/va+lue", :invalid_topic_filter_wildcard},
          {"$share//things/#", :invalid_shared_topic_filter},
          {"$share/readers", :invalid_shared_topic_filter},
          {"$share/rea+ders/things/#", :invalid_shared_topic_filter}
        ] do
      assert {:error, %Error{code: ^code}} = Topic.validate_filter(filter)
    end
  end

  test "normalizes one filter or an ordered list" do
    assert {:ok, ["things/#"]} = Topic.normalize_filters("things/#")
    assert {:ok, ["things/+", "events/#"]} = Topic.normalize_filters(["things/+", "events/#"])
    assert {:error, %Error{code: :invalid_topic_filters}} = Topic.normalize_filters([])

    assert {:error, %Error{code: :invalid_topic_filter_wildcard}} =
             Topic.normalize_filters(["things/+value"])
  end

  test "matches filters by MQTT topic levels" do
    assert Topic.matches?("things/value", "things/value")
    assert Topic.matches?("things/+", "things/value")
    assert Topic.matches?("things/#", "things")
    assert Topic.matches?("things/#", "things/value/next")
    assert Topic.matches?("$share/readers/things/+", "things/value")
    refute Topic.matches?("things/+", "things/value/next")
    refute Topic.matches?("+/value", "$system/value")
    refute Topic.matches?("bad+filter", "things/value")
    refute Topic.matches?("things/#", "things/+value")
  end
end
