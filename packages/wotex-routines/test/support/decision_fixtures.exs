Code.require_file("continuation_fixtures.exs", __DIR__)

defmodule Wotex.Routines.Test.DecisionFixtures do
  @moduledoc false

  alias Wotex.Routines.{Arbitration, Basis, Collection, Decision, Kernel, Validation}
  alias Wotex.Routines.Test.ContinuationFixtures, as: F

  @spec elapsed(map()) :: map()
  def elapsed(c) do
    bases =
      Enum.map(c.context["bases"], fn basis ->
        basis = put_in(basis, ["evidence", "require_source_time"], false)
        {:ok, digest} = Basis.semantic_digest(basis, c.limits)
        %{basis | "semantic_digest" => digest}
      end)

    digests = Map.new(bases, &{&1["id"], &1["semantic_digest"]})

    registry =
      Enum.map(c.context["registry"], fn ref ->
        if Map.has_key?(digests, ref["id"]),
          do: %{ref | "semantic_digest" => digests[ref["id"]]},
          else: ref
      end)

    bindings =
      Map.new(c.context["bindings"], fn {name, binding} ->
        {name, put_in(binding, ["basis", "semantic_digest"], digests[binding["basis"]["id"]])}
      end)

    %{c | context: %{c.context | "bases" => bases, "registry" => registry, "bindings" => bindings}}
  end

  @spec input(map(), [map()]) :: map()
  def input(c, members) do
    ids = Enum.map(members, & &1.program.data["ir_digest"])

    entries =
      Enum.map(members, fn member ->
        %{
          "program" => member.program.data,
          "event" => member.event,
          "snapshot" => %{member.snapshot | "active_programs" => ids},
          "prior" => %{"original" => nil, "busy" => nil, "edge" => nil}
        }
      end)

    %{
      "format" => "wotex.routines.collection-input@2",
      "membership" => %{"generation" => "membership:1", "programs" => ids},
      "entries" => entries,
      "time" => c.time
    }
  end

  @spec members(map(), [tuple()], map()) :: [map()]
  def members(c, definitions, changes \\ %{}) do
    Enum.map(definitions, fn {id, input, domain} ->
      binding = %{
        c.context["bindings"]["actuator"]
        | "thing_id" => "urn:output:" <> domain,
          "resource_roles" => %{"target" => "resource:" <> domain}
      }

      context = put_in(c.context, ["bindings", "actuator"], binding)

      F.compile(
        %{c | context: context},
        Map.merge(%{"id" => id, "steps" => F.effect("apply", input)}, changes)
      )
    end)
  end

  @spec collection(map(), map()) :: Collection.t()
  def collection(c, input) do
    {:ok, collection} = Collection.evaluate(input, c.profile, c.limits)
    collection
  end

  # Prepares independently valid direct points without applying Collection's
  # aggregate semantics, so its active/pending/coherence guards can be tested.
  @spec claimed(map(), map()) :: Collection.t()
  def claimed(c, input) do
    transitions =
      input["entries"]
      |> Enum.sort_by(& &1["program"]["ir_digest"])
      |> Enum.map(fn entry ->
        {:ok, result} =
          Kernel.advance(
            entry["program"],
            entry["event"],
            entry["snapshot"],
            input["time"],
            entry["prior"],
            c.profile,
            c.limits
          )

        %{"program_digest" => entry["program"]["ir_digest"], "result" => result}
      end)

    proposals = Enum.flat_map(transitions, & &1["result"]["proposals"])

    data = %{
      "format" => "wotex.routines.collection@2",
      "input" => input,
      "profile" => c.profile.data,
      "json_limits" => c.limits.data,
      "transitions" => transitions,
      "proposals" => proposals,
      "proposal_states" =>
        Enum.map(proposals, &%{"step_original" => &1["step_original"], "status" => "proposed"})
    }

    {:ok, digest} = Validation.hash(data, c.limits)
    %Collection{data: Map.put(data, "collection_digest", digest)}
  end

  @spec decision(map(), Collection.t()) :: Decision.t()
  def decision(c, collection) do
    {:ok, decision} = proof(fn -> Decision.new(collection, c.profile, c.limits) end)
    decision
  end

  @spec context(map(), Collection.t(), pos_integer(), map() | nil) :: map()
  def context(c, collection, batch \\ 1, dispositions \\ nil) do
    dispositions =
      dispositions ||
        Map.new(
          collection.data["proposals"],
          &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}}
        )

    {:ok, arbitration} = Arbitration.decide(collection, dispositions, batch, c.profile, c.limits)

    %{
      "input" => collection.data["input"],
      "dispositions" => dispositions,
      "batch_limit" => batch,
      "arbitration" => arbitration
    }
  end

  @spec retained(Collection.t()) :: map()
  def retained(collection) do
    results = Map.new(collection.data["transitions"], &{&1["program_digest"], &1["result"]})

    update_in(collection.data["input"], ["entries"], fn entries ->
      Enum.map(entries, fn entry ->
        result = results[entry["program"]["ir_digest"]]
        run = result["run"]

        event = %{
          "kind" => "resume",
          "original" => run["original"],
          "program_digest" => run["program_digest"]
        }

        %{
          entry
          | "event" => event,
            "prior" => %{"original" => run, "busy" => nil, "edge" => result["edge"]}
        }
      end)
    end)
  end

  @spec proof((-> term())) :: term()
  def proof(fun) do
    previous = Process.put(:routines_transition_verifying, true)

    try do
      fun.()
    after
      if previous == nil,
        do: Process.delete(:routines_transition_verifying),
        else: Process.put(:routines_transition_verifying, previous)
    end
  end
end
