defmodule Wotex.Lab.Component do
  @moduledoc """
  The execution port a trusted host component implements for the runner.

  A component module also implements `Wotex.Lab.Plugin` for identity,
  capabilities, child specifications and its manifest. `execute/3` runs one
  typed step: `operation` and `input` come from the scenario definition as
  data, and `context` carries the attempt id, step id, a derived seed, the
  remaining budget in milliseconds, the owning instance, the attempt's private
  work directory, the pids of the children the runner started for this
  component and the values of the steps this step depends on. A component
  returns `{:ok, value}` or `{:error, %Wotex.Lab.Error{}}`; anything else is
  an invalid return that the runner records and treats as a failed step.
  Raising, throwing or exiting inside `execute/3` never escapes the attempt.
  """

  @type context :: %{
          attempt_id: String.t(),
          step_id: String.t(),
          seed: non_neg_integer(),
          remaining_ms: non_neg_integer(),
          instance: pid(),
          work_dir: Path.t(),
          children: [pid()],
          results: %{String.t() => term()},
          budgets: map()
        }

  @doc "Executes one typed step."
  @callback execute(String.t(), term(), context()) :: {:ok, term()} | {:error, Wotex.Lab.Error.t()}
end
