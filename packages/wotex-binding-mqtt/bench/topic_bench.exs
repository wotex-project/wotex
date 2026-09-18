alias Wotex.Binding.MQTT.{Broker, Command, Topic}

# Four Topic Filter shapes in rotation: an exact filter, a single-level
# wildcard, a multi-level wildcard and an MQTT 5 shared subscription. Only the
# first filter matches the probe Topic Name, whatever the list length.
filter = fn
  index when rem(index, 4) == 0 -> "things/zone-#{index}/properties/temperature"
  index when rem(index, 4) == 1 -> "things/+/properties/p#{index}"
  index when rem(index, 4) == 2 -> "things/zone-#{index}/#"
  index -> "$share/consumers/things/zone-#{index}/events/+"
end

probe = "things/zone-0/properties/temperature"
{:ok, broker} = Broker.new("mqtts://broker.example:8883")

inputs =
  Enum.map([{"1 filter", 1}, {"16 filters", 16}, {"256 filters", 256}], fn {label, count} ->
    filters = Enum.map(0..(count - 1)//1, filter)

    names =
      Enum.map(0..(count - 1)//1, &"things/urn:example:thing:#{&1}/properties/temperature")

    {label, %{filters: filters, names: names}}
  end)

Benchee.run(
  %{
    "normalize_filters/1" => fn %{filters: filters} ->
      {:ok, ^filters} = Topic.normalize_filters(filters)
    end,
    "validate_name/1 for each Topic Name" => fn %{names: names} ->
      Enum.each(names, fn name -> :ok = Topic.validate_name(name) end)
    end,
    "matches?/2 of one Topic Name against each filter" => fn %{filters: filters} ->
      1 = Enum.count(filters, &Topic.matches?(&1, probe))
    end,
    "Command.subscribe/4" => fn %{filters: filters} ->
      {:ok, _} = Command.subscribe(broker, :subscribeevent, filters, qos: 1)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/topic.md",
     title: "# Topic Name and Topic Filter handling",
     description: """
     `Wotex.Binding.MQTT.Topic` and SUBSCRIBE command construction over one, 16
     and 256 Topic Filters, 256 being the package's filter cardinality limit.
     The filters rotate through an exact filter, a single-level `+` wildcard, a
     multi-level `#` wildcard and an MQTT 5 `$share` subscription. The match job
     tests one Topic Name against every filter, validating both on each call,
     as `Wotex.Binding.MQTT.Transport` does for every delivery;
     `Wotex.Binding.MQTT.Command.subscribe/4` validates the list and the QoS.
     """}
  ]
)
