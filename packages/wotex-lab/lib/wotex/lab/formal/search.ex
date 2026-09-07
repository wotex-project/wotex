defmodule Wotex.Lab.Formal.Search do
  @moduledoc """
  The engine-independent verification session.

  `run/2` drives one verification through an `execute` function that sends a
  command to an engine and returns `{:ok, output}` or `{:error, reason}`.
  The session loads the model, runs the bounded property search, expands a
  solution into an ordered counterexample with `show path`, and, when the
  bounded search finds nothing, attempts exhaustion with an unbounded-depth
  search. Every command is built by the closed serializer and every reply is
  read by the bounded parsers, so this module can be exercised with captured
  engine replies. Deadline accounting is explicit: each command receives the
  time that remains, and a spent deadline is a timeout before the command.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Formal.{Output, Result, Serializer}

  @type execute :: (String.t(), pos_integer() -> {:ok, binary()} | {:error, term()})

  @type session :: %{
          base: Result.t(),
          load: String.t(),
          command: String.t(),
          module: String.t(),
          initial_term: String.t(),
          property: Serializer.property(),
          deadline: integer(),
          ceiling: pos_integer(),
          exhaustion?: boolean()
        }

  @doc "Runs the session; the outcome is a result, a typed error or the engine's error term."
  @spec run(session(), execute()) :: {:ok, Result.t()} | {:error, term()}
  def run(session, execute) when is_function(execute, 2) do
    with {:ok, _loaded} <- command(session, session.load, execute),
         {:ok, output} <- command(session, session.command, execute),
         {:ok, search} <- Output.search(output, max_bytes: session.ceiling) do
      case search.solutions do
        [%{state: state} | _rest] -> counterexample(session, search, state, execute)
        [] -> exhaust(session, search, execute)
      end
    end
  end

  @doc "Maps a session outcome to the result the profile returns."
  @spec conclude({:ok, Result.t()} | {:error, term()}, Result.t(), non_neg_integer()) :: Result.t()
  def conclude({:ok, %Result{} = result}, _base, _reaped), do: result

  def conclude({:error, %Error{} = error}, base, _reaped),
    do: %{
      base
      | status: :error,
        error: %{code: error.code, phase: error.phase, details: error.details}
    }

  def conclude({:error, {:engine_timeout, _message}}, base, reaped),
    do: %{base | status: :timeout, error: %{code: :engine_timeout, reaped: reaped}}

  def conclude({:error, {:engine_error, type}}, base, _reaped),
    do: %{base | status: :error, error: %{code: :engine_error, type: type}}

  def conclude({:error, other}, base, _reaped),
    do: %{base | status: :error, error: %{code: :engine_error, reason: inspect(other, limit: 20)}}

  @doc "True when an outcome ended in an engine timeout in either phase."
  @spec timed_out?({:ok, Result.t()} | {:error, term()}) :: boolean()
  def timed_out?({:error, {:engine_timeout, _message}}), do: true
  def timed_out?({:ok, %Result{error: %{code: :exhaustion_timeout}}}), do: true
  def timed_out?(_outcome), do: false

  defp counterexample(session, search, state, execute) do
    with {:ok, path_command} <- Serializer.path(state),
         {:ok, path_output} <- command(session, path_command, execute),
         {:ok, steps} <- Output.path(path_output, max_bytes: session.ceiling) do
      {:ok,
       %{
         session.base
         | status: :counterexample,
           explored: explored(search),
           counterexample: steps,
           exhaustion: %{basis: :none, states: nil}
       }}
    end
  end

  defp exhaust(%{exhaustion?: false} = session, search, _execute) do
    {:ok,
     %{
       session.base
       | status: :inconclusive,
         explored: explored(search),
         exhaustion: %{basis: :depth_bound, states: nil}
     }}
  end

  defp exhaust(session, search, execute) do
    with {:ok, command} <-
           Serializer.search(session.module, session.initial_term, session.property,
             max_solutions: 1,
             max_depth: :unbounded
           ),
         {:ok, output} <- command(session, command, execute),
         {:ok, complete} <- Output.search(output, max_bytes: session.ceiling) do
      case complete.solutions do
        [] ->
          {:ok,
           %{
             session.base
             | status: :verified_in_model,
               explored: explored(search),
               exhaustion: %{basis: :complete_search, states: complete.states}
           }}

        _deeper ->
          # A solution beyond the bound: the bounded answer stays inconclusive.
          {:ok,
           %{
             session.base
             | status: :inconclusive,
               explored: explored(search),
               exhaustion: %{basis: :depth_bound, states: nil}
           }}
      end
    else
      {:error, {:engine_timeout, _message}} ->
        {:ok,
         %{
           session.base
           | status: :inconclusive,
             explored: explored(search),
             exhaustion: %{basis: :depth_bound, states: nil},
             error: %{code: :exhaustion_timeout}
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp command(session, text, execute) do
    remaining = session.deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, {:engine_timeout, "deadline exhausted before the command"}}
    else
      case execute.(text, remaining) do
        {:ok, output} when byte_size(output) > session.ceiling ->
          {:error,
           Error.new(:output_overflow, :engine, "engine output exceeds the ceiling",
             details: %{bytes: byte_size(output)}
           )}

        other ->
          other
      end
    end
  end

  defp explored(search), do: %{states: search.states, rewrites: search.rewrites}
end
