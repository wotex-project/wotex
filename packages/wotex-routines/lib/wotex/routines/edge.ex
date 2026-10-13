defmodule Wotex.Routines.Edge do
  @moduledoc "Retained reported-edge qualification over explicit continuous facts and caller-owned elapsed time."

  alias Wotex.Routines.{
    Compiler,
    Error,
    Event,
    Limits,
    ObservationView,
    Profile,
    Snapshot,
    Time,
    Validation
  }

  @fields ~w(format program_digest binding binding_basis epoch clock_generation last_elapsed_ms last_receipt_ms last_sequence last_fact_id last_fact_digest baseline candidate_since_ms cooldown_until_ms last_original)
  @sample ~w(last_receipt_ms last_sequence last_fact_id last_fact_digest)
  @basis ~w(profile_digest source_id source_epoch source_time_basis)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Checks closed retained edge identity, source/clock basis and coupled coordinates."
  @spec new(term(), term(), Profile.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, program, profile, limits) do
    with {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <- Validation.fields(data, @fields),
         :ok <- identity(data, program),
         :ok <- coordinates(data, limits),
         :ok <- sample(data, limits) do
      {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Revalidates retained edge data before projection."
  @spec to_map(term(), term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(edge, program, profile, limits) do
    with {:ok, edge} <- new(edge, program, profile, limits), do: {:ok, edge.data}
  end

  @doc "Advances only new qualified continuous reports; eligibility is inert and grants no authority."
  @spec advance(term(), term(), term(), term(), term(), Profile.t(), Limits.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def advance(program, event, snapshot, time, prior, profile, limits) do
    with {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, event} <- Event.to_map(event, limits),
         {:ok, snapshot} <- Snapshot.to_map(snapshot, program, profile, limits),
         {:ok, time} <- Time.to_map(time, limits),
         {:ok, prior} <- retained(prior, program, profile, limits),
         {:ok, fact} <- input(program, event, snapshot),
         {:ok, digest} <- Validation.hash(fact, limits),
         {:ok, result} <- evaluate(program, event, snapshot, time, prior, fact, digest, limits),
         {:ok, _} <- new(result["edge"], program, profile, limits) do
      {:ok, result}
    end
  end

  defp retained(nil, _, _, _), do: {:ok, nil}
  defp retained(prior, program, profile, limits), do: to_map(prior, program, profile, limits)

  defp identity(data, program) do
    trigger = program["ir"]["trigger"]
    basis = data["binding_basis"]

    with true <-
           trigger["kind"] == "edge" and data["binding"] == trigger["binding"] and
             data["program_digest"] == program["ir_digest"],
         :ok <- Validation.choice(data["format"], ["wotex.routines.edge@1"], "/format"),
         :ok <- Validation.fields(basis, @basis),
         :ok <- Validation.text(basis["source_id"], "/binding_basis/source_id"),
         :ok <- Validation.text(basis["source_epoch"], "/binding_basis/source_epoch"),
         :ok <- optional_digest(basis["source_time_basis"]),
         :ok <- Validation.text(data["epoch"], "/epoch"),
         :ok <- Validation.text(data["clock_generation"], "/clock_generation"),
         true <-
           basis["profile_digest"] ==
             program["context"]["bindings"][data["binding"]]["basis"]["semantic_digest"] do
      :ok
    else
      false -> Error.refusal(:stale_edge)
      error -> error
    end
  end

  defp optional_digest(nil), do: :ok
  defp optional_digest(value), do: Validation.digest(value, "/digest")

  defp coordinates(data, limits) do
    with :ok <- Validation.integer(data["last_elapsed_ms"], limits, "/last_elapsed_ms", 0),
         :ok <- Validation.integer(data["cooldown_until_ms"], limits, "/cooldown_until_ms", 0),
         :ok <- Validation.choice(data["baseline"], [true, false, nil], "/baseline"),
         :ok <- candidate(data, limits) do
      if data["last_original"] == nil,
        do: :ok,
        else: Validation.text(data["last_original"], "/last_original")
    end
  end

  defp candidate(%{"candidate_since_ms" => nil}, _), do: :ok

  defp candidate(data, limits) do
    with :ok <- Validation.integer(data["candidate_since_ms"], limits, "/candidate_since_ms", 0),
         true <- data["baseline"] == false and data["candidate_since_ms"] <= data["last_elapsed_ms"] do
      :ok
    else
      false -> Error.refusal(:incoherent_edge)
      error -> error
    end
  end

  defp sample(data, limits) do
    if Enum.all?(@sample, &(data[&1] == nil)) do
      if data["baseline"] == nil and data["candidate_since_ms"] == nil,
        do: :ok,
        else: Error.refusal(:incoherent_edge)
    else
      with :ok <- Validation.integer(data["last_sequence"], limits, "/last_sequence", 0),
           :ok <- Validation.integer(data["last_receipt_ms"], limits, "/last_receipt_ms", 0),
           :ok <- Validation.text(data["last_fact_id"], "/last_fact_id"),
           :ok <- Validation.digest(data["last_fact_digest"], "/last_fact_digest") do
        if data["last_receipt_ms"] <= data["last_elapsed_ms"],
          do: :ok,
          else: Error.refusal(:incoherent_edge)
      end
    end
  end

  defp input(program, event, snapshot) do
    trigger = program["ir"]["trigger"]
    fact = snapshot["facts"][trigger["binding"]]

    if trigger["kind"] == "edge" and event["kind"] == "fact" and
         event["program_digest"] == program["ir_digest"] and event["binding"] == trigger["binding"] and
         is_map(fact) and event["fact_id"] == fact["id"],
       do: {:ok, fact},
       else: Error.refusal(:foreign_edge_fact)
  end

  defp evaluate(program, event, snapshot, time, prior, fact, digest, limits) do
    edge = initial(program, snapshot, time)

    replaced =
      prior == nil or
        Map.take(prior, ~w(binding_basis epoch clock_generation)) !=
          Map.take(edge, ~w(binding_basis epoch clock_generation))

    retained = if replaced, do: edge, else: prior
    values = ObservationView.values(program, snapshot, time, limits)
    qualified = fact["continuity"] == "continuous" and values[edge["binding"]] != :unknown

    cond do
      conflict?(replaced, prior, fact, digest) ->
        Error.refusal(:conflicting_edge_fact)

      elapsed_regressed?(replaced, prior, time) ->
        output(reset(prior), false, "unqualified")

      not qualified ->
        output(reset(retained), false, "unqualified")

      duplicate?(replaced, prior, fact) ->
        output(%{prior | "last_elapsed_ms" => time["elapsed_ms"]}, false, "duplicate")

      sample_regressed?(replaced, prior, fact) ->
        output(reset(%{prior | "last_elapsed_ms" => time["elapsed_ms"]}), false, "unqualified")

      true ->
        edge = remember(retained, fact, digest, time)
        active = active(program["ir"]["trigger"], values[edge["binding"]], edge)
        transition(edge, active, event, time, program["ir"]["trigger"], limits)
    end
  end

  defp conflict?(true, _, _, _), do: false

  defp conflict?(false, prior, fact, digest),
    do: same_identity?(prior, fact) and prior["last_fact_digest"] != digest

  defp elapsed_regressed?(true, _, _), do: false
  defp elapsed_regressed?(false, prior, time), do: time["elapsed_ms"] < prior["last_elapsed_ms"]
  defp duplicate?(true, _, _), do: false
  defp duplicate?(false, prior, fact), do: same_identity?(prior, fact)
  defp sample_regressed?(true, _, _), do: false
  defp sample_regressed?(false, prior, fact), do: regressed?(prior, fact)

  defp same_identity?(edge, fact),
    do: edge["last_fact_id"] == fact["id"] or edge["last_sequence"] == fact["sequence"]

  defp regressed?(%{"last_sequence" => nil}, _), do: false

  defp regressed?(edge, fact),
    do: fact["sequence"] <= edge["last_sequence"] or fact["receipt_ms"] < edge["last_receipt_ms"]

  defp reset(edge), do: %{edge | "baseline" => nil, "candidate_since_ms" => nil}

  defp initial(program, snapshot, time) do
    binding = program["ir"]["trigger"]["binding"]

    %{
      "format" => "wotex.routines.edge@1",
      "program_digest" => program["ir_digest"],
      "binding" => binding,
      "binding_basis" => snapshot["binding_bases"][binding],
      "epoch" => time["epoch"],
      "clock_generation" => time["clock_generation"],
      "last_elapsed_ms" => time["elapsed_ms"],
      "last_receipt_ms" => nil,
      "last_sequence" => nil,
      "last_fact_id" => nil,
      "last_fact_digest" => nil,
      "baseline" => nil,
      "candidate_since_ms" => nil,
      "cooldown_until_ms" => 0,
      "last_original" => nil
    }
  end

  defp remember(edge, fact, digest, time),
    do: %{
      edge
      | "last_elapsed_ms" => time["elapsed_ms"],
        "last_receipt_ms" => fact["receipt_ms"],
        "last_sequence" => fact["sequence"],
        "last_fact_id" => fact["id"],
        "last_fact_digest" => digest
    }

  defp active(%{"direction" => direction, "hysteresis" => nil}, {:known, value}, _)
       when is_boolean(value), do: if(direction == "rising", do: value, else: not value)

  defp active(%{"direction" => direction, "hysteresis" => hysteresis}, {:known, value}, edge) do
    cond do
      direction == "rising" and value >= hysteresis["enter"] -> true
      direction == "rising" and value <= hysteresis["exit"] -> false
      direction == "falling" and value <= hysteresis["enter"] -> true
      direction == "falling" and value >= hysteresis["exit"] -> false
      edge["candidate_since_ms"] != nil -> true
      true -> edge["baseline"]
    end
  end

  defp transition(%{"baseline" => nil} = edge, active, _, _, _, _),
    do: output(%{edge | "baseline" => active}, false, "baseline")

  defp transition(edge, active, _, _, _, _) when active in [nil, false],
    do: output(%{edge | "baseline" => active, "candidate_since_ms" => nil}, false, "stable")

  defp transition(%{"baseline" => true} = edge, true, _, _, _, _),
    do: output(edge, false, "stable")

  defp transition(edge, true, event, time, trigger, limits) do
    since = edge["candidate_since_ms"] || time["elapsed_ms"]

    cond do
      time["elapsed_ms"] < edge["cooldown_until_ms"] ->
        output(%{edge | "baseline" => true, "candidate_since_ms" => nil}, false, "cooldown")

      time["elapsed_ms"] - since < trigger["debounce_ms"] ->
        output(%{edge | "candidate_since_ms" => since}, false, "debouncing")

      true ->
        until = time["elapsed_ms"] + trigger["cooldown_ms"]

        with :ok <- Validation.integer(until, limits, "/cooldown_until_ms", 0) do
          output(
            %{
              edge
              | "baseline" => true,
                "candidate_since_ms" => nil,
                "cooldown_until_ms" => until,
                "last_original" => event["original"]
            },
            true,
            "eligible"
          )
        end
    end
  end

  defp output(edge, eligible, reason),
    do: {:ok, %{"edge" => edge, "eligible" => eligible, "reason" => reason}}
end
