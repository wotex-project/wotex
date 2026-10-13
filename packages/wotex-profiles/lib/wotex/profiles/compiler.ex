defmodule Wotex.Profiles.Compiler do
  @moduledoc """
  Bounded selected-closure compilation into inert interpretation plans.

  Installed bindings, contracts, profile data and capture are explicit input.
  No function selects executable code, discovers a device, installs trust or
  authorizes an interaction. Consumers retain exact producer-artifact pins.
  """

  alias Wotex.Profiles.{Capture, Checked, Closure, Error, Grammar, Instance, Projection}

  @contract Path.expand("../../../priv/contracts/compiler.json", __DIR__)
  @external_resource @contract
  @manifest Jason.decode!(File.read!(@contract))
  {:ok, manifest_bytes} = Wotex.JSON.encode(@manifest)

  @identity %{
    "id" => "urn:wotex:profiles:compiler",
    "version" => "1.0.0",
    "sha256" =>
      Base.encode16(:crypto.hash(:sha256, "wotex.profile.compiler@1\n" <> manifest_bytes),
        case: :lower
      )
  }

  @doc "Returns the installed immutable compiler-contract identity, separately from archive identity."
  @spec identity() :: %{String.t() => String.t()}
  def identity, do: @identity

  @doc "Checks static mechanics and returns the exact reachable reference array used by closure identity."
  @spec references(term(), term(), term()) :: {:ok, [map()]} | {:error, Error.t()}
  def references(profile, closure, limits) do
    with {:ok, state} <- Closure.prepare(profile, closure, limits),
         {:ok, _, state} <- channels(state),
         references = Closure.references(state),
         {:ok, _, _} <- Grammar.admit(references, state.limits) do
      {:ok, references}
    end
  end

  @doc "Checks installed closure, selectors and mechanics without capture or I/O."
  @spec check(term(), term(), term()) :: {:ok, Checked.t()} | {:error, Error.t()}
  def check(profile, closure, limits) do
    with {:ok, state} <- Closure.prepare(profile, closure, limits),
         {:ok, plans, state} <- channels(state),
         {:ok, closure_sha256} <- closure_identity(state),
         {:ok, limits_sha256} <-
           Grammar.identity("wotex.profile.limits@1", state.limits.data, state.limits),
         data = %{
           "profile_sha256" => state.profile.semantic_sha256,
           "closure_sha256" => closure_sha256,
           "compiler_ref" => identity(),
           "binding" => state.binding.ref,
           "channel_plans" => plans,
           "limits_sha256" => limits_sha256
         },
         {:ok, _, _} <- Grammar.admit(data, state.limits) do
      {:ok,
       %Checked{
         data: data,
         inputs: %{
           "profile" => state.profile.data,
           "closure" => state.closure,
           "limits" => state.limits.data
         }
       }}
    end
  end

  defp closure_identity(state) do
    case Wotex.JSON.encode(Closure.references(state), Grammar.options(state.limits)) do
      {:ok, bytes} -> {:ok, Grammar.hash("wotex.profile.closure@1\n" <> bytes)}
      _ -> Error.refusal(:input_limit, "/closure")
    end
  end

  @doc "Rechecks static mechanics and matches the explicit capture before creating an inert projection."
  @spec compile(term(), term(), term(), term()) :: {:ok, Projection.t()} | {:error, Error.t()}
  def compile(profile, closure, capture, limits) do
    with {:ok, checked} <- check(profile, closure, limits),
         binding =
           Enum.find(
             checked.inputs["closure"]["bindings"],
             &(Map.take(&1, ~w(id version sha256)) == checked.data["binding"])
           ),
         {:ok, capture} <- Capture.new(capture, binding, checked.inputs["limits"]),
         {:ok, _, _} <-
           Grammar.admit(
             %{
               "profile" => checked.inputs["profile"],
               "closure" => checked.inputs["closure"],
               "capture" => capture.data
             },
             checked.inputs["limits"]
           ),
         :ok <- fingerprint(checked.inputs["profile"]["fingerprint"], capture.data["fields"]),
         data =
           checked.data
           |> Map.delete("limits_sha256")
           |> Map.merge(%{
             "capture_digest" => capture.data["digest"],
             "capture_epoch" => capture.data["capture_epoch"]
           }),
         {:ok, _, _} <- Grammar.admit(data, checked.inputs["limits"]) do
      {:ok, %Projection{data: data, inputs: Map.put(checked.inputs, "capture", capture.data)}}
    end
  end

  defp fingerprint(predicates, fields) do
    if Enum.all?(predicates, fn predicate ->
         Map.has_key?(fields, predicate["field"]) and
           fields[predicate["field"]] in predicate["values"]
       end), do: :ok, else: Error.refusal(:fingerprint_mismatch, "/fingerprint")
  end

  defp channels(state) do
    result =
      Enum.reduce_while(
        Enum.with_index(state.profile.data["channels"]),
        {:ok, [], state, 2, 1},
        fn {channel, index}, {:ok, plans, state, bytes, nodes} ->
          path = "/channels/" <> Integer.to_string(index)

          case channel(channel, state, path) do
            {:ok, plan, state} ->
              accumulate(plan, plans, state, bytes, nodes)

            error ->
              {:halt, error}
          end
        end
      )

    case result do
      {:ok, plans, state, _, _} -> {:ok, Enum.reverse(plans), state}
      error -> error
    end
  end

  defp accumulate(plan, plans, state, bytes, nodes) do
    case Wotex.JSON.encode(plan, Grammar.options(state.limits)) do
      {:ok, encoded} ->
        size = bytes + byte_size(encoded) + 1
        count = nodes + nodes(plan)

        if size <= state.limits.data["max_bytes"] and count <= state.limits.data["max_nodes"],
          do: {:cont, {:ok, [plan | plans], state, size, count}},
          else: {:halt, Error.refusal(:input_limit, "/channels")}

      _ ->
        {:halt, Error.refusal(:input_limit, "/channels")}
    end
  end

  defp nodes(value) when is_list(value), do: 1 + Enum.reduce(value, 0, &(nodes(&1) + &2))
  defp nodes(value) when is_map(value), do: 1 + Enum.reduce(Map.values(value), 0, &(nodes(&1) + &2))
  defp nodes(_), do: 1

  defp channel(channel, state, path) do
    case Closure.definition(channel["semantic"], state, path <> "/semantic") do
      {:ok, definition, next} ->
        case mechanics(channel, definition.data, state.binding.data, state.limits, path) do
          :ok -> {:ok, plan(channel, definition.data, nil), next}
          error -> excluded(channel, definition.data, next, error)
        end

      error ->
        definition = state.index[{channel["semantic"]["id"], channel["semantic"]["version"]}]
        data = if definition && definition.kind == :definition, do: definition.data, else: nil
        excluded(channel, data, state, error)
    end
  end

  defp excluded(channel, definition, state, {:error, %Error{code: code}} = error) do
    if not channel["required"] and
         code in [
           :missing_reference,
           :unsupported_binding,
           :unsupported_selector,
           :unsupported_semantics,
           :out_of_domain,
           :codec_required,
           :numeric_limit
         ], do: {:ok, plan(channel, definition, Atom.to_string(code)), state}, else: error
  end

  defp plan(channel, definition, reason) do
    %{
      "channel_id" => channel["id"],
      "affordance" => channel["affordance"],
      "semantic" => channel["semantic"],
      "definition" => if(definition, do: Map.delete(definition, "annotations"), else: nil),
      "selector" => channel["selector"],
      "conversion" => channel["conversion"],
      "invalid_values" => channel["invalid_values"],
      "required" => channel["required"],
      "operations" => if(reason, do: [], else: channel["operations"]),
      "disposition" => if(reason, do: "excluded", else: "supported"),
      "reason" => reason
    }
  end

  defp mechanics(channel, definition, binding, limits, path) do
    with true <- Enum.all?(channel["operations"], &(&1 in binding["operations"])),
         :ok <- selector(channel["selector"], binding["selector_schema"], limits, path),
         true <-
           definition["unit"] == nil or definition["value_schema"]["type"] in ~w(integer number),
         :ok <-
           Grammar.each(
             channel["invalid_values"],
             &Instance.c02(&1, binding["raw_value_schema"], limits, path <> "/invalid_values")
           ) do
      conversion(
        channel["conversion"],
        binding["raw_value_schema"],
        definition["value_schema"],
        limits,
        path
      )
    else
      false -> Error.refusal(:unsupported_semantics, path)
      error -> error
    end
  end

  defp selector(value, schema, limits, path) do
    case Instance.json(value, schema, limits, path <> "/selector") do
      :ok ->
        :ok

      {:error, %Error{code: :out_of_domain}} ->
        Error.refusal(:unsupported_selector, path <> "/selector")

      error ->
        error
    end
  end

  defp conversion(nil, raw, target, _, path) do
    if raw["type"] == target["type"] or
         (raw["type"] in ~w(integer number) and target["type"] in ~w(integer number)),
       do: :ok,
       else: Error.refusal(:unsupported_semantics, path)
  end

  defp conversion(%{"kind" => "affine"}, raw, target, _, path) do
    if raw["type"] in ~w(integer number) and target["type"] in ~w(integer number),
      do: :ok,
      else: Error.refusal(:unsupported_semantics, path)
  end

  defp conversion(%{"kind" => "table", "entries" => entries}, raw, target, limits, path),
    do:
      Grammar.each(entries, fn entry ->
        with :ok <- Instance.c02(entry["source"], raw, limits, path <> "/conversion"),
             do: Instance.c02(entry["target"], target, limits, path <> "/conversion")
      end)
end
