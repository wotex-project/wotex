defmodule Wotex.Lab.Formal.Output do
  @moduledoc """
  Parsers for the Maude output the profile relies on.

  `search/1` reads a `search` reply into either a solution list with the
  explored state count or an explicit no-solution report; a reply carrying a
  `Warning:` line, no recognizable outcome, or unreadable numbers is
  malformed. `path/1` reads a `show path` reply into ordered steps of state
  number, rule label and state term. Both refuse output above `max_bytes`.

  Parsing is intentionally narrower than general Maude syntax and never invokes
  the engine. Missing expected output or a recognized warning produces a typed
  failure. The parser does not validate every line as a complete Maude
  transcript; callers retain raw output within their evidence boundary.
  """

  alias Wotex.Lab.Error

  @default_max_bytes 1_048_576

  @type search :: %{
          solutions: [%{number: pos_integer(), state: non_neg_integer()}],
          states: non_neg_integer(),
          rewrites: non_neg_integer(),
          time_ms: non_neg_integer() | nil
        }

  @type step :: %{state: non_neg_integer(), rule: String.t() | nil, term: String.t()}

  @doc "Parses a `search` reply."
  @spec search(binary(), keyword()) :: {:ok, search()} | {:error, Error.t()}
  def search(output, opts \\ []) when is_binary(output) do
    with :ok <- bounded(output, Keyword.get(opts, :max_bytes, @default_max_bytes)),
         :ok <- no_warnings(output),
         {:ok, states, rewrites, time_ms} <- statistics(output) do
      solutions =
        ~r/Solution (\d+) \(state (\d+)\)/
        |> Regex.scan(output)
        |> Enum.map(fn [_all, number, state] ->
          %{number: String.to_integer(number), state: String.to_integer(state)}
        end)

      cond do
        solutions != [] ->
          {:ok, %{solutions: solutions, states: states, rewrites: rewrites, time_ms: time_ms}}

        String.contains?(output, "No solution.") ->
          {:ok, %{solutions: [], states: states, rewrites: rewrites, time_ms: time_ms}}

        true ->
          {:error,
           Error.new(
             :malformed_output,
             :parse,
             "search reply has neither a solution nor a no-solution report"
           )}
      end
    end
  end

  @doc "Parses a `show path` reply into ordered steps."
  @spec path(binary(), keyword()) :: {:ok, [step()]} | {:error, Error.t()}
  def path(output, opts \\ []) when is_binary(output) do
    with :ok <- bounded(output, Keyword.get(opts, :max_bytes, @default_max_bytes)),
         :ok <- no_warnings(output) do
      steps =
        output
        |> String.split("\n")
        |> Enum.reduce({[], nil}, &step/2)
        |> elem(0)
        |> Enum.reverse()

      if steps == [],
        do: {:error, Error.new(:malformed_output, :parse, "path reply has no states")},
        else: {:ok, steps}
    end
  end

  defp step(line, {steps, rule}) do
    cond do
      match = Regex.run(~r/\Astate (\d+), Room: (.+)\z/, String.trim_trailing(line)) ->
        [_all, state, term] = match
        {[%{state: String.to_integer(state), rule: rule, term: String.trim(term)} | steps], nil}

      match = Regex.run(~r/\A===\[ c?rl \[([A-Za-z]+)\]/, line) ->
        {steps, Enum.at(match, 1)}

      true ->
        {steps, rule}
    end
  end

  defp bounded(output, max_bytes) when byte_size(output) <= max_bytes, do: :ok

  defp bounded(output, max_bytes),
    do:
      {:error,
       Error.new(:output_overflow, :parse, "engine output exceeds the ceiling",
         details: %{bytes: byte_size(output), max_bytes: max_bytes}
       )}

  defp no_warnings(output) do
    case Regex.run(~r/^(Warning|Error): (.*)$/m, output) do
      nil ->
        :ok

      [_all, kind, text] ->
        {:error,
         Error.new(:engine_warning, :parse, "engine reported a problem",
           details: %{kind: kind, text: String.slice(text, 0, 200)}
         )}
    end
  end

  defp statistics(output) do
    case Regex.run(~r/states: (\d+)\s+rewrites: (\d+) in (\d+)ms cpu/, output) do
      [_all, states, rewrites, time] ->
        {:ok, String.to_integer(states), String.to_integer(rewrites), String.to_integer(time)}

      nil ->
        {:error, Error.new(:malformed_output, :parse, "search reply carries no statistics")}
    end
  end
end
