defmodule Wotex.Lab.Formal.Serializer do
  @moduledoc """
  The closed serializer from abstract terms and property ids to Maude commands.

  Only atoms from the model's finite sorts and bounded natural numbers reach
  the command text, and every property is a fixed pattern from a table keyed
  by id. Caller input therefore cannot become command syntax: a string, an
  unknown atom, a negative or oversized number, or an unknown property id is
  refused before any command exists. The `such that` conditions are fixed
  text as well. This serializer is Lab-owned because the published ExMaude
  IoT and AI encoders describe different models.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Formal.Abstraction

  @bands %{cold: "cold", comfort: "comfort", hot: "hot"}
  @switches %{on: "on", off: "off"}
  @energies %{within: "within", over: "over"}
  @actions %{heat: "heat", cool: "cool"}
  @max_nat 16

  @properties %{
    no_simultaneous_heat_cool: %{
      pattern: "room(B:Band, on, on, E:Energy, D:Decision, A:Nat, G:Nat, N:Nat)",
      condition: nil,
      description: "heat and cool are never simultaneously admitted"
    },
    no_effect_without_decision: %{
      pattern: "room(B:Band, H:Switch, C:Switch, E:Energy, D:Decision, A:Nat, G:Nat, N:Nat)",
      condition: "N:Nat > G:Nat",
      description: "no simulated effect without a matching decision: effects never exceed grants"
    },
    no_stale_dispatch: %{
      pattern:
        "room(B:Band, H:Switch, C:Switch, E:Energy, dispatched(X:Action, T:Nat), A:Nat, G:Nat, N:Nat)",
      condition: "T:Nat >= maxAge",
      description: "a stale observation cannot authorize a dispatch"
    },
    energy_limit_not_bypassed: %{
      pattern: "room(B:Band, on, C:Switch, over, D:Decision, A:Nat, G:Nat, N:Nat)",
      condition: nil,
      description: "an energy-limit refusal cannot be bypassed by reordering"
    },
    no_duplicate_effect: %{
      pattern: "room(B:Band, H:Switch, C:Switch, E:Energy, D:Decision, A:Nat, G:Nat, N:Nat)",
      condition: "N:Nat > G:Nat",
      description:
        "a duplicate intent cannot create a second simulated effect: effects never exceed grants"
    }
  }

  @type property ::
          :no_simultaneous_heat_cool
          | :no_effect_without_decision
          | :no_stale_dispatch
          | :energy_limit_not_bypassed
          | :no_duplicate_effect

  @doc "Property ids with their descriptions."
  @spec properties() :: %{property() => String.t()}
  def properties, do: Map.new(@properties, fn {id, %{description: text}} -> {id, text} end)

  @doc "Serializes an abstract room to a Maude term."
  @spec term(Abstraction.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def term(%{
        band: band,
        heater: heater,
        cooler: cooler,
        energy: energy,
        decision: decision,
        age: age,
        grants: grants,
        effects: effects
      }) do
    with {:ok, band} <- closed(band, @bands, "band"),
         {:ok, heater} <- closed(heater, @switches, "heater"),
         {:ok, cooler} <- closed(cooler, @switches, "cooler"),
         {:ok, energy} <- closed(energy, @energies, "energy"),
         {:ok, decision} <- decision(decision),
         {:ok, age} <- nat(age, "age"),
         {:ok, grants} <- nat(grants, "grants"),
         {:ok, effects} <- nat(effects, "effects") do
      {:ok,
       "room(#{band}, #{heater}, #{cooler}, #{energy}, #{decision}, #{age}, #{grants}, #{effects})"}
    end
  end

  def term(_),
    do: {:error, Error.new(:invalid_term, :serialize, "abstract room must be a complete map")}

  @doc "Builds a bounded `search` command for a property from an initial term."
  @spec search(String.t(), String.t(), property(), keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def search(module, initial, property, opts)
      when is_binary(module) and is_binary(initial) and is_list(opts) do
    with {:ok, module} <- module_name(module),
         {:ok, %{pattern: pattern, condition: condition}} <- property(property),
         {:ok, initial} <- reserialize(initial),
         {:ok, solutions} <- bound(Keyword.get(opts, :max_solutions, 1), "max_solutions"),
         {:ok, depth} <- depth(Keyword.get(opts, :max_depth, 100)) do
      bounds = if depth == :unbounded, do: "[#{solutions}]", else: "[#{solutions}, #{depth}]"
      base = "search #{bounds} in #{module} : #{initial} =>* #{pattern}"
      {:ok, if(condition, do: base <> " such that " <> condition <> " .", else: base <> " .")}
    end
  end

  def search(_, _, _, _),
    do:
      {:error, Error.new(:invalid_command, :serialize, "search inputs must be strings and options")}

  @doc "Builds the `show path` command for a solution state number."
  @spec path(non_neg_integer()) :: {:ok, String.t()} | {:error, Error.t()}
  def path(state) when is_integer(state) and state >= 0 and state <= 1_000_000,
    do: {:ok, "show path #{state} ."}

  def path(_),
    do:
      {:error,
       Error.new(:invalid_command, :serialize, "state number must be a bounded natural number")}

  @doc "Builds the `load` command for a model path that the profile already verified."
  @spec load(Path.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def load(path) when is_binary(path) do
    if Regex.match?(~r/\A[A-Za-z0-9_\/\.\-]+\.maude\z/, path),
      do: {:ok, "load #{path}"},
      else:
        {:error,
         Error.new(
           :invalid_command,
           :serialize,
           "model path contains characters outside the admitted set"
         )}
  end

  defp closed(value, table, field) when is_atom(value) do
    case Map.fetch(table, value) do
      {:ok, text} ->
        {:ok, text}

      :error ->
        {:error,
         Error.new(:invalid_term, :serialize, "#{field} is outside the model sort",
           details: %{field: field}
         )}
    end
  end

  defp closed(_, _, field),
    do:
      {:error,
       Error.new(:invalid_term, :serialize, "#{field} must be an atom of the model sort",
         details: %{field: field}
       )}

  defp decision(:no_decision), do: {:ok, "noDecision"}

  defp decision({status, action, age}) when status in [:granted, :dispatched] do
    with {:ok, action} <- closed(action, @actions, "action"),
         {:ok, age} <- nat(age, "decision age") do
      {:ok, "#{status}(#{action}, #{age})"}
    end
  end

  defp decision(_),
    do: {:error, Error.new(:invalid_term, :serialize, "decision is outside the model sort")}

  defp nat(value, _) when is_integer(value) and value >= 0 and value <= @max_nat,
    do: {:ok, Integer.to_string(value)}

  defp nat(_, field),
    do:
      {:error,
       Error.new(:invalid_term, :serialize, "#{field} must be a natural number at most #{@max_nat}",
         details: %{field: field}
       )}

  defp module_name(module) do
    if Regex.match?(~r/\A[A-Z][A-Z0-9\-]{0,63}\z/, module),
      do: {:ok, module},
      else:
        {:error,
         Error.new(:invalid_command, :serialize, "module name is outside the admitted form")}
  end

  defp property(id) when is_map_key(@properties, id), do: {:ok, Map.fetch!(@properties, id)}

  defp property(id),
    do:
      {:error,
       Error.new(:unknown_property, :serialize, "property is not in the table",
         details: %{property: id}
       )}

  # An initial term is admitted only if it parses back into an abstract room and
  # re-serializes to itself, so no foreign text survives.
  defp reserialize(initial) do
    with {:ok, abstract} <- Abstraction.from_term(initial),
         {:ok, ^initial} <- term(abstract) do
      {:ok, initial}
    else
      _ ->
        {:error, Error.new(:invalid_term, :serialize, "initial term is not a canonical room state")}
    end
  end

  defp bound(value, _) when is_integer(value) and value >= 1 and value <= 64,
    do: {:ok, Integer.to_string(value)}

  defp bound(_, field),
    do:
      {:error,
       Error.new(:invalid_command, :serialize, "#{field} must be between 1 and 64",
         details: %{field: field}
       )}

  defp depth(:unbounded), do: {:ok, :unbounded}

  defp depth(value) when is_integer(value) and value >= 1 and value <= 10_000,
    do: {:ok, Integer.to_string(value)}

  defp depth(_),
    do:
      {:error,
       Error.new(
         :invalid_command,
         :serialize,
         "max_depth must be between 1 and 10000 or :unbounded"
       )}
end
