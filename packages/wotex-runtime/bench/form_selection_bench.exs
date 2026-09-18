Code.require_file("support/things.exs", __DIR__)

alias Wotex.Runtime.Bench.Things
alias Wotex.Runtime.FormSelector

profiles = Things.profiles()

inputs =
  Map.new(Things.form_sizes(), fn {label, count} ->
    {label, Things.thing_description(1, forms: count)}
  end)

Benchee.run(
  %{
    "select Property Form (readproperty)" => fn td ->
      {:ok, _} = FormSelector.select(td, :property, "p1", :readproperty, profiles)
    end,
    "select Action Form (invokeaction)" => fn td ->
      {:ok, _} = FormSelector.select(td, :action, "calibrate", :invokeaction, profiles)
    end,
    "select top-level Form (readallproperties)" => fn td ->
      {:ok, _} = FormSelector.select_thing(td, :readallproperties, profiles)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/form_selection.md",
     title: "# Form and binding-profile selection",
     description: """
     `Wotex.Runtime.FormSelector.select/5` and `select_thing/3` against two
     binding profiles (MQTT, then HTTP and HTTPS). Each Interaction Affordance and
     the top-level `forms` array hold one, 16 or 128 Forms, the last of which is
     the only compatible one: a relative `https` href resolved against the
     Thing Description `base`. Every earlier Form uses a `coap` URI that neither
     profile declares, so each input is the worst-case scan at that size; 128 is
     the Runtime Form scan limit.
     """}
  ]
)
