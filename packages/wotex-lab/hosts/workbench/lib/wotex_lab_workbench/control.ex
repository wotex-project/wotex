defmodule WotexLabWorkbench.Control do
  @moduledoc """
  Shared control-plane operations for HTTP and generated clients.

  Scenario and metric catalogue reads are inert. Evidence and run lookups
  require the caller's already-admitted room and return only what that room
  retains. `run_view/1` is the bounded run projection: identity, status,
  timing, assertions, evidence digest, the named decision and the read-back
  effect, without tensors, timeseries or parameters.

  `admit_mutation/4` is the closed admission of the three host-opted-in HTTP
  mutations `startRun`, `cancelRun` and `approveDecision`. It validates the
  `Idempotency-Key`, the body fields and their bounds, the `deadline_ms`
  wait bound and, for `startRun`, the experiment and string parameters through
  `WotexLabWorkbench.Experiments`, the admission of the LiveView form. The
  result names the session command and a `WotexLabWorkbench.Room` mutation
  whose SHA-256 fingerprint covers the operation, run identifier and body
  without the deadline. `mutate/2` hands that mutation to the room, which
  executes it at most once per key. This module opens no session and starts no
  room; the controller verifies the session and admits rate and concurrency
  limits first.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Record
  alias Wotex.Lab.Metrics.Catalogue
  alias Wotex.Lab.Scenario
  alias WotexLabWorkbench.{Experiments, Room, Run, Runs}

  @max_deadline_ms 30_000
  @max_parameters 16
  @max_parameter_bytes 32
  @idempotency_key ~r/\A[\x21-\x7E]{1,128}\z/
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @decision_fields ~w(id status thing_id action_name input proposal_digest state_revision expires_at)
  @approval_fields ~w(decision_id thing_id action_name input proposal_digest state_revision expires_at)

  @typedoc "An HTTP control mutation operation."
  @type operation :: :start_run | :cancel_run | :approve_decision

  @typedoc "An admitted mutation: the session command, the wait bound and the room mutation."
  @type admitted :: %{
          command: :run | :cancel | :approve,
          deadline_ms: pos_integer(),
          mutation: Room.mutation()
        }

  @doc "Returns every admitted Lab scenario as the versioned public descriptor."
  @spec scenarios() :: [map()]
  def scenarios do
    Enum.map(Scenario.admitted(), &Scenario.to_map/1)
  end

  @doc "Returns one admitted scenario descriptor by exact identifier."
  @spec fetch_scenario(term()) :: {:ok, map()} | {:error, Error.t()}
  def fetch_scenario(id) do
    case Scenario.fetch_admitted(id) do
      {:ok, scenario} -> {:ok, Scenario.to_map(scenario)}
      {:error, %Error{} = error} -> {:error, %{error | phase: :control_api}}
    end
  end

  @doc "Returns one evidence record retained by the supplied room and exact digest."
  @spec fetch_evidence(pid(), term()) :: {:ok, map()} | {:error, Error.t()}
  def fetch_evidence(room, "sha256:" <> hex = digest)
      when is_pid(room) and byte_size(hex) == 64 do
    if hex =~ ~r/\A[0-9a-f]{64}\z/ do
      room
      |> Room.runs()
      |> Enum.find(&(&1.record_digest == digest))
      |> case do
        %{record: %Record{} = record} -> {:ok, Record.to_map(record)}
        _missing -> {:error, error(:unknown_evidence, "evidence record is not retained")}
      end
    else
      {:error, error(:invalid_record_id, "record digest is malformed")}
    end
  end

  def fetch_evidence(_room, _digest),
    do: {:error, error(:invalid_record_id, "record digest is malformed")}

  @doc "Projects a run into the bounded JSON-compatible map of the control API."
  @spec run_view(Run.t()) :: map()
  def run_view(%Run{} = run) do
    %{
      "id" => run.id,
      "experiment" => run.experiment,
      "attempt" => run.attempt,
      "status" => Atom.to_string(run.status),
      "started_at" => DateTime.to_iso8601(run.started_at),
      "duration_ms" => run.duration_ms,
      "record_digest" => run.record_digest,
      "assertions" => Enum.map(run.assertions, &assertion_view/1),
      "decision" => run.decision && Map.take(run.decision, @decision_fields),
      "effect" => Runs.plain(run.effect),
      "error" => run.error && Map.new(run.error, fn {key, value} -> {to_string(key), value} end)
    }
  end

  @doc "Returns one run retained by the supplied room as its control projection."
  @spec fetch_run(pid(), term()) :: {:ok, map()} | {:error, Error.t()}
  def fetch_run(room, run_id)
      when is_pid(room) and is_binary(run_id) and byte_size(run_id) <= 64 do
    case Room.fetch_run(room, run_id) do
      {:ok, run} -> {:ok, run_view(run)}
      {:error, _} -> {:error, unknown_run()}
    end
  end

  def fetch_run(_, _), do: {:error, unknown_run()}

  @doc "Admits one mutation's idempotency key and closed JSON body."
  @spec admit_mutation(operation(), String.t() | nil, term(), term()) ::
          {:ok, admitted()} | {:error, Error.t()}
  def admit_mutation(operation, run_id, key, body) do
    with :ok <- idempotency_key(key),
         :ok <- run_id(operation, run_id),
         {:ok, deadline_ms} <- deadline(body),
         {:ok, session_command, command} <- command(operation, run_id, body) do
      digest =
        {operation, run_id, Map.delete(body, "deadline_ms")}
        |> :erlang.term_to_binary([:deterministic])
        |> then(&:crypto.hash(:sha256, &1))

      {:ok,
       %{
         command: session_command,
         deadline_ms: deadline_ms,
         mutation: %{key: key, fingerprint: digest, command: command}
       }}
    end
  end

  @doc """
  Runs an admitted mutation in the room and waits at most its deadline.

  The tag reports whether the room executed the command or replayed a retained
  identity; `:refused` means nothing ran.
  """
  @spec mutate(pid(), admitted()) ::
          {:ok, :executed | :replayed, map()}
          | {:error, :executed | :replayed | :refused, Error.t()}
  def mutate(room, %{mutation: mutation, deadline_ms: deadline_ms}) when is_pid(room) do
    deadline_at = System.monotonic_time(:millisecond) + deadline_ms

    case Room.control(room, mutation, deadline_at, deadline_ms) do
      {mode, {:ok, %Run{} = run}} -> {:ok, mode, run_view(run)}
      {mode, {:error, %Error{} = error}} -> {:error, mode, error}
      {:error, %Error{} = error} -> {:error, :refused, error}
    end
  catch
    :exit, {:timeout, _} ->
      {:error, :refused, error(:deadline_exceeded, "deadline passed while the room worked")}

    :exit, _ ->
      {:error, :refused, error(:room_unavailable, "room is unavailable")}
  end

  defp idempotency_key(key) when is_binary(key) do
    if Regex.match?(@idempotency_key, key),
      do: :ok,
      else: {:error, error(:invalid_idempotency_key, "Idempotency-Key is malformed")}
  end

  defp idempotency_key(_),
    do: {:error, error(:invalid_idempotency_key, "Idempotency-Key is required")}

  defp run_id(:start_run, nil), do: :ok

  defp run_id(operation, run_id)
       when operation in [:cancel_run, :approve_decision] and is_binary(run_id) and
              byte_size(run_id) in 1..64,
       do: :ok

  defp run_id(_, _), do: {:error, unknown_run()}

  defp deadline(%{"deadline_ms" => deadline_ms})
       when is_integer(deadline_ms) and deadline_ms in 1..@max_deadline_ms,
       do: {:ok, deadline_ms}

  defp deadline(_),
    do: {:error, invalid_body("/deadline_ms", "deadline_ms must be 1..#{@max_deadline_ms}")}

  defp command(:start_run, nil, body) do
    parameters = Map.get(body, "parameters", %{})

    with :ok <- closed(body, ~w(experiment_id parameters deadline_ms)),
         {:ok, id} <- bounded_string(body, "experiment_id", 64),
         :ok <- parameter_strings(parameters),
         {:ok, experiment} <- Experiments.fetch(id),
         :ok <- declared(experiment, parameters),
         {:ok, params} <- Experiments.admit(experiment, parameters) do
      {:ok, :run, {:run, id, params}}
    end
  end

  defp command(:cancel_run, run_id, body) do
    with :ok <- closed(body, ~w(deadline_ms)), do: {:ok, :cancel, {:cancel, run_id}}
  end

  defp command(:approve_decision, run_id, body) do
    with :ok <- closed(body, ["deadline_ms" | @approval_fields]),
         {:ok, decision_id} <- bounded_string(body, "decision_id", 64),
         {:ok, thing_id} <- bounded_string(body, "thing_id", 256),
         {:ok, action_name} <- bounded_string(body, "action_name", 64),
         {:ok, digest} <- proposal_digest(body),
         {:ok, input} <- number(body, "input"),
         {:ok, revision} <- integer(body, "state_revision"),
         {:ok, expires_at} <- integer(body, "expires_at") do
      named = %{"thing_id" => thing_id, "action_name" => action_name, "input" => input}

      approval = %{
        "decision_id" => decision_id,
        "proposal_digest" => digest,
        "revision" => Integer.to_string(revision),
        "expires_at" => Integer.to_string(expires_at)
      }

      {:ok, :approve, {:approve, run_id, named, approval}}
    end
  end

  defp closed(body, fields) do
    case Enum.reject(Map.keys(body), &(&1 in fields)) do
      [] -> :ok
      _ -> {:error, invalid_body("/", "body contains an unknown field")}
    end
  end

  defp bounded_string(body, field, max) do
    case Map.get(body, field) do
      value when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= max ->
        {:ok, value}

      _ ->
        {:error, invalid_body("/" <> field, "#{field} must be a string of 1..#{max} bytes")}
    end
  end

  defp proposal_digest(body) do
    case Map.get(body, "proposal_digest") do
      digest when is_binary(digest) and byte_size(digest) == 71 ->
        if Regex.match?(@digest, digest), do: {:ok, digest}, else: malformed_digest()

      _ ->
        malformed_digest()
    end
  end

  defp malformed_digest,
    do: {:error, invalid_body("/proposal_digest", "proposal_digest must be a sha256 digest")}

  defp number(body, field) do
    case Map.get(body, field) do
      value when is_number(value) -> {:ok, value}
      _ -> {:error, invalid_body("/" <> field, "#{field} must be a number")}
    end
  end

  defp integer(body, field) do
    case Map.get(body, field) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, invalid_body("/" <> field, "#{field} must be an integer")}
    end
  end

  defp parameter_strings(parameters)
       when is_map(parameters) and map_size(parameters) <= @max_parameters do
    if Enum.all?(parameters, fn {_, value} ->
         is_binary(value) and byte_size(value) <= @max_parameter_bytes
       end),
       do: :ok,
       else: {:error, invalid_body("/parameters", "parameters must be short strings")}
  end

  defp parameter_strings(_),
    do: {:error, invalid_body("/parameters", "parameters must be an object of strings")}

  defp declared(experiment, parameters) do
    names = Enum.map(experiment.parameters, & &1.name)

    if Enum.all?(Map.keys(parameters), &(&1 in names)),
      do: :ok,
      else:
        {:error,
         Error.new(:unknown_parameter, :admission, "parameter is not declared", path: "/parameters")}
  end

  defp assertion_view(assertion),
    do: %{
      "id" => assertion.id,
      "status" => Atom.to_string(assertion.status),
      "note" => assertion.note
    }

  defp invalid_body(path, message), do: Error.new(:invalid_body, :control_api, message, path: path)
  defp unknown_run, do: error(:unknown_run, "run is not retained")

  @doc "Returns the complete versioned metric catalogue as JSON-compatible data."
  @spec metrics_catalogue() :: map()
  def metrics_catalogue do
    %{
      "schema_version" => Catalogue.version(),
      "metrics" => Enum.map(Catalogue.metrics(), &metric_map/1)
    }
  end

  defp metric_map(metric) do
    %{
      "id" => Atom.to_string(metric.id),
      "name" => metric.name,
      "version" => metric.version,
      "kind" => Atom.to_string(metric.type),
      "unit" => Atom.to_string(metric.unit),
      "dimensions" => Enum.map(metric.dimensions, &Atom.to_string/1),
      "scope" => Atom.to_string(metric.scope),
      "buckets" => metric.buckets,
      "description" => metric.description
    }
  end

  defp error(code, message), do: Error.new(code, :control_api, message)
end
