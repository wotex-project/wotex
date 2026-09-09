defmodule Wotex.Lab.Runner.Definition do
  @moduledoc """
  A revision-pinned scenario definition: typed steps, fixtures, assertions and
  faults as data.

  A definition names its `id` and `revision`, the fixture digests it relies
  on (`%{name => "sha256:..."}`), the capabilities it requires, ordered steps
  (`%{"id", "capability", "operation", "input", "depends_on"}`), assertions
  over step values (`%{"id", "step", "equals"}` or with `"key"` for a map
  member), optional faults keyed by step id (`"raise"`, `"throw"`, `"exit"`,
  `"invalid_return"` or `"hang"`) that the runner injects instead of the
  component call, and upstream references. Construction validates shapes,
  unique step ids, known dependencies, acyclic order and input sizes; it
  executes nothing and creates no atoms from input.
  """

  alias Wotex.Lab.{Error, Options}

  @faults ~w(raise throw exit invalid_return hang)
  @max_steps 100_000
  @max_ingress_bytes 16_777_216
  @step_keys ~w(id capability operation input depends_on)

  @type step :: %{
          id: String.t(),
          capability: String.t(),
          operation: String.t(),
          input: term(),
          depends_on: [String.t()]
        }

  @type t :: %__MODULE__{
          id: String.t(),
          revision: String.t(),
          fixtures: %{String.t() => String.t()},
          capabilities: [String.t()],
          steps: [step()],
          assertions: [map()],
          faults: %{String.t() => String.t()},
          upstream: [String.t()]
        }

  @enforce_keys [:id, :revision, :capabilities, :steps]
  defstruct id: nil,
            revision: nil,
            fixtures: %{},
            capabilities: [],
            steps: [],
            assertions: [],
            faults: %{},
            upstream: []

  @doc "Builds and validates a definition from keyword options."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    with :ok <-
           Options.validate(opts, [
             :id,
             :revision,
             :fixtures,
             :capabilities,
             :steps,
             :assertions,
             :faults,
             :upstream
           ]),
         definition =
           struct(
             __MODULE__,
             Map.merge(%{id: nil, revision: nil, capabilities: [], steps: []}, Map.new(opts))
           ),
         :ok <- identity(definition),
         {:ok, steps} <- steps(definition.steps),
         :ok <- capabilities(definition.capabilities, steps),
         :ok <- fixtures(definition.fixtures),
         :ok <- assertions(definition.assertions, steps),
         :ok <- faults(definition.faults, steps),
         :ok <- upstream(definition.upstream) do
      {:ok, %{definition | steps: steps}}
    end
  end

  def new(_),
    do: {:error, Error.new(:invalid_definition, :preflight, "definition must be a keyword list")}

  @doc "Steps in dependency order; every dependency precedes its dependants."
  @spec order(t()) :: [step()]
  def order(%__MODULE__{steps: steps}) do
    {ordered, _} =
      Enum.reduce(steps, {[], MapSet.new()}, fn step, acc -> visit(step, steps, acc) end)

    Enum.reverse(ordered)
  end

  @doc false
  @spec revalidate(term()) :: {:ok, t()} | {:error, Error.t()}
  def revalidate(%__MODULE__{} = definition) do
    steps =
      Enum.map(definition.steps, fn
        %{
          id: id,
          capability: capability,
          operation: operation,
          input: input,
          depends_on: dependencies
        } ->
          %{
            "id" => id,
            "capability" => capability,
            "operation" => operation,
            "input" => input,
            "depends_on" => dependencies
          }

        invalid ->
          invalid
      end)

    case new(
           id: definition.id,
           revision: definition.revision,
           fixtures: definition.fixtures,
           capabilities: definition.capabilities,
           steps: steps,
           assertions: definition.assertions,
           faults: definition.faults,
           upstream: definition.upstream
         ) do
      {:ok, rebuilt} -> if rebuilt == definition, do: {:ok, rebuilt}, else: invalid_forgery()
      {:error, error} -> {:error, error}
    end
  rescue
    _ -> invalid_forgery()
  end

  def revalidate(_), do: invalid_forgery()

  defp visit(step, steps, {ordered, seen}) do
    if MapSet.member?(seen, step.id) do
      {ordered, seen}
    else
      {ordered, seen} =
        Enum.reduce(step.depends_on, {ordered, seen}, fn dependency, acc ->
          visit(Enum.find(steps, &(&1.id == dependency)), steps, acc)
        end)

      {[step | ordered], MapSet.put(seen, step.id)}
    end
  end

  defp identity(%{id: id, revision: revision}) do
    if Options.identifier?(id) and is_binary(revision) and byte_size(revision) in 1..128 and
         String.valid?(revision),
       do: :ok,
       else:
         {:error,
          Error.new(:invalid_definition, :preflight, "id and revision must be bounded identifiers")}
  end

  defp steps(steps) when is_list(steps) and length(steps) in 1..@max_steps do
    with {:ok, typed} <- Enum.reduce_while(steps, {:ok, []}, &typed_step/2),
         typed = Enum.reverse(typed),
         :ok <- unique(typed),
         :ok <- dependencies(typed),
         :ok <- acyclic(typed) do
      {:ok, typed}
    end
  end

  defp steps(_),
    do:
      {:error, Error.new(:invalid_definition, :preflight, "steps must be a bounded non-empty list")}

  defp typed_step(
         %{"id" => id, "capability" => capability, "operation" => operation} = step,
         {:ok, acc}
       )
       when is_binary(id) and is_binary(capability) and is_binary(operation) do
    depends_on = Map.get(step, "depends_on", [])

    with :ok <- known_step_fields(step),
         :ok <- step_id(id),
         :ok <- step_capability(capability, id),
         :ok <- step_operation(operation, id),
         :ok <- step_dependencies(depends_on, id),
         :ok <- step_input(Map.get(step, "input"), id) do
      {:cont,
       {:ok,
        [
          %{
            id: id,
            capability: capability,
            operation: operation,
            input: Map.get(step, "input"),
            depends_on: depends_on
          }
          | acc
        ]}}
    else
      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  defp typed_step(_, _),
    do:
      {:halt,
       {:error,
        Error.new(:invalid_step, :preflight, "step needs id, capability and operation strings",
          path: "/steps"
        )}}

  defp known_step_fields(step) do
    if Map.keys(step) -- @step_keys == [],
      do: :ok,
      else: invalid_step("step contains unknown fields", "/steps")
  end

  defp step_id(id) do
    if Options.identifier?(id),
      do: :ok,
      else: invalid_step("step id must be a bounded identifier", "/steps")
  end

  defp step_capability(capability, id) do
    if Options.identifier?(capability),
      do: :ok,
      else: invalid_step("capability must be a bounded identifier", "/steps/" <> id)
  end

  defp step_operation(operation, id) do
    if byte_size(operation) in 1..128 and String.valid?(operation),
      do: :ok,
      else: invalid_step("operation must be 1..128 bytes", "/steps/" <> id)
  end

  defp step_dependencies(dependencies, id) do
    valid =
      is_list(dependencies) and Enum.all?(dependencies, &Options.identifier?/1) and
        Enum.uniq(dependencies) == dependencies

    if valid,
      do: :ok,
      else: invalid_step("depends_on must be a list of step ids", "/steps/" <> id)
  end

  defp step_input(input, id) do
    valid =
      json_value?(input) and
        byte_size(:erlang.term_to_binary(input, [:deterministic])) <= @max_ingress_bytes

    if valid,
      do: :ok,
      else: invalid_step("step input must be bounded JSON data", "/steps/" <> id)
  end

  defp invalid_step(message, path),
    do: {:error, Error.new(:invalid_step, :preflight, message, path: path)}

  defp unique(steps) do
    ids = Enum.map(steps, & &1.id)

    if Enum.uniq(ids) == ids,
      do: :ok,
      else:
        {:error,
         Error.new(:duplicate_step, :preflight, "step ids must be unique",
           details: %{ids: ids -- Enum.uniq(ids)}
         )}
  end

  defp dependencies(steps) do
    ids = MapSet.new(steps, & &1.id)

    case Enum.find(steps, fn step -> Enum.any?(step.depends_on, &(not MapSet.member?(ids, &1))) end) do
      nil ->
        :ok

      step ->
        {:error,
         Error.new(:unknown_dependency, :preflight, "step depends on an unknown step",
           path: "/steps/" <> step.id
         )}
    end
  end

  defp acyclic(steps) do
    graph = Map.new(steps, &{&1.id, &1.depends_on})

    case Enum.find(steps, fn step -> cycle?(step.id, graph, [step.id]) end) do
      nil ->
        :ok

      step ->
        {:error,
         Error.new(:dependency_cycle, :preflight, "step dependencies form a cycle",
           path: "/steps/" <> step.id
         )}
    end
  end

  defp cycle?(id, graph, trail) do
    Enum.any?(Map.fetch!(graph, id), fn dependency ->
      dependency in trail or cycle?(dependency, graph, [dependency | trail])
    end)
  end

  defp capabilities(capabilities, steps)
       when is_list(capabilities) and length(capabilities) in 1..64 do
    used = steps |> Enum.map(& &1.capability) |> Enum.uniq()

    cond do
      not Enum.all?(capabilities, &Options.identifier?/1) or Enum.uniq(capabilities) != capabilities ->
        {:error,
         Error.new(:invalid_definition, :preflight, "capabilities must be unique identifiers")}

      used -- capabilities != [] ->
        {:error,
         Error.new(
           :undeclared_capability,
           :preflight,
           "a step uses a capability the definition does not require",
           details: %{capabilities: used -- capabilities}
         )}

      true ->
        :ok
    end
  end

  defp capabilities(_, _),
    do: {:error, Error.new(:invalid_definition, :preflight, "capabilities must be a list")}

  defp fixtures(fixtures) when is_map(fixtures) and map_size(fixtures) <= 1_024 do
    if Enum.all?(fixtures, fn {name, digest} ->
         valid_fixture_name?(name) and is_binary(digest) and
           Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, digest)
       end),
       do: :ok,
       else:
         {:error,
          Error.new(
            :invalid_fixture_digest,
            :preflight,
            "fixture digests must be sha256 values keyed by name"
          )}
  end

  defp fixtures(_),
    do: {:error, Error.new(:invalid_fixture_digest, :preflight, "fixtures must be a bounded map")}

  defp assertions(assertions, steps) when is_list(assertions) and length(assertions) <= 1_024 do
    ids = MapSet.new(steps, & &1.id)

    if Enum.all?(assertions, &valid_assertion?(&1, ids)),
      do: :ok,
      else:
        {:error,
         Error.new(
           :invalid_assertion,
           :preflight,
           "assertions need id, a known step and an equals value"
         )}
  end

  defp assertions(_, _),
    do: {:error, Error.new(:invalid_assertion, :preflight, "assertions must be a bounded list")}

  defp valid_assertion?(%{"id" => id, "step" => step} = assertion, ids) do
    [
      Map.keys(assertion) -- ~w(id step equals key) == [],
      Options.identifier?(id),
      MapSet.member?(ids, step),
      Map.has_key?(assertion, "equals"),
      json_value?(assertion["equals"]),
      not Map.has_key?(assertion, "key") or is_binary(assertion["key"])
    ]
    |> Enum.all?()
  end

  defp valid_assertion?(_, _), do: false

  defp faults(faults, steps) when is_map(faults) and map_size(faults) <= @max_steps do
    ids = MapSet.new(steps, & &1.id)

    if Enum.all?(faults, fn {step, fault} -> MapSet.member?(ids, step) and fault in @faults end),
      do: :ok,
      else:
        {:error,
         Error.new(
           :invalid_fault,
           :preflight,
           "faults must name known steps and one of #{Enum.join(@faults, ", ")}"
         )}
  end

  defp faults(_, _),
    do: {:error, Error.new(:invalid_fault, :preflight, "faults must be a map")}

  defp upstream(refs) when is_list(refs) and length(refs) <= 256 do
    if Enum.all?(refs, &(is_binary(&1) and byte_size(&1) in 1..256 and String.valid?(&1))),
      do: :ok,
      else:
        {:error,
         Error.new(:invalid_definition, :preflight, "upstream references must be bounded strings")}
  end

  defp upstream(_),
    do: {:error, Error.new(:invalid_definition, :preflight, "upstream must be a list")}

  defp valid_fixture_name?(name) when is_binary(name) and byte_size(name) in 1..1_024 do
    String.valid?(name) and Path.type(name) == :relative and ".." not in Path.split(name) and
      not String.contains?(name, <<0>>)
  end

  defp valid_fixture_name?(_), do: false

  defp json_value?(nil), do: true
  defp json_value?(value) when is_boolean(value) or is_binary(value), do: true
  defp json_value?(value) when is_integer(value), do: true
  defp json_value?(value) when is_float(value), do: true
  defp json_value?(value) when is_list(value), do: Enum.all?(value, &json_value?/1)

  defp json_value?(value) when is_map(value) do
    Enum.all?(value, fn {key, member} -> is_binary(key) and json_value?(member) end)
  end

  defp json_value?(_), do: false

  defp invalid_forgery,
    do: {:error, Error.new(:invalid_definition, :preflight, "definition struct is forged")}
end
