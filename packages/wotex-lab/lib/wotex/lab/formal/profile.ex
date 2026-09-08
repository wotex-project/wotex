# Compiled only when the optional ex_maude package is present; the base package
# and every other Lab profile stay usable without a formal engine.
# ExCoveralls excludes this optional host integration from the base-profile
# denominator. Its own Maude-tagged suite remains the WLB.09 evidence gate when
# an operator supplies the pinned executable.
# coveralls-ignore-start
if Code.ensure_loaded?(ExMaude.Pool) do
  defmodule Wotex.Lab.Formal.Profile do
    @moduledoc """
    The explicit, optional ex_maude verification profile for `thermal-control-v1`.

    `new/1` admits a profile: a catalogued model whose file matches its manifest
    digest, an explicitly supplied Maude executable whose SHA-256 the caller
    pins, an explicit pool name and bounded limits with hard ceilings. Missing
    or unverifiable binaries give `:unsupported`, never an empty success.
    `child_spec/1` returns the published `ExMaude.Pool.child_spec/1` for the
    caller's own supervisor; the profile starts nothing by itself and never
    downloads a binary.

    `verify/5` runs one bounded search through the closed serializer: the
    model is loaded into the checked-out worker, the property's search runs
    under the depth, solution, deadline and output ceilings, a solution is
    expanded with `show path` into an ordered counterexample, and a bounded
    no-solution answer is `:inconclusive` unless the exhaustion attempt (an
    unbounded-depth search that terminates within the remaining deadline)
    establishes `:complete_search`. A timeout stops the worker so the pool
    replaces it. Because a closed port does not end a Maude process that is
    busy inside a search, the profile records the operating-system process ids
    behind the worker before each command and sends `SIGKILL` to any that
    survive a stopped worker; `stop/2` does the same for a whole pool. Results
    are `Wotex.Lab.Formal.Result` values and never an authorization token: the
    profile has no access to any Thing or policy.
    """

    alias Wotex.Lab.Error
    alias Wotex.Lab.Evidence.Digest
    alias Wotex.Lab.Formal.{Abstraction, Model, Result, Search, Serializer}
    alias Wotex.Lab.Telemetry

    @default_limits %{
      max_depth: 100,
      max_solutions: 1,
      deadline_ms: 5_000,
      max_output_bytes: 1_048_576
    }
    @ceilings %{
      max_depth: 1_000,
      max_solutions: 8,
      deadline_ms: 60_000,
      max_output_bytes: 8_388_608
    }
    @version_timeout_ms 5_000
    @reap_grace_ms 1_000

    @type t :: %__MODULE__{
            model: Model.t(),
            binary: Path.t(),
            binary_digest: String.t(),
            engine: %{maude: String.t(), ex_maude: String.t()},
            pool: atom(),
            limits: %{
              max_depth: pos_integer(),
              max_solutions: pos_integer(),
              deadline_ms: pos_integer(),
              max_output_bytes: pos_integer()
            }
          }

    @enforce_keys [:model, :binary, :binary_digest, :engine, :pool, :limits]
    defstruct @enforce_keys

    @doc "Default limits and their hard ceilings."
    @spec limits() :: %{defaults: map(), ceilings: map()}
    def limits, do: %{defaults: @default_limits, ceilings: @ceilings}

    @doc "Admits a profile from `:model`, `:binary`, `:binary_digest`, `:pool` and optional `:limits`."
    @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
    def new(opts) when is_list(opts) do
      with {:ok, model} <- Model.fetch(Keyword.get(opts, :model, :thermal_control_v1)),
           {:ok, model} <- Model.verify(model),
           {:ok, pool} <- pool(Keyword.get(opts, :pool)),
           {:ok, limits} <- limits(Keyword.get(opts, :limits, %{})),
           {:ok, binary, digest} <-
             binary(Keyword.get(opts, :binary), Keyword.get(opts, :binary_digest)),
           {:ok, version} <- engine_version(binary) do
        {:ok,
         %__MODULE__{
           model: model,
           binary: binary,
           binary_digest: digest,
           engine: %{maude: version, ex_maude: ex_maude_version()},
           pool: pool,
           limits: limits
         }}
      end
    end

    @doc "The pool child specification for the caller's supervisor: one port worker, no overflow."
    @spec child_spec(t()) :: Supervisor.child_spec()
    def child_spec(%__MODULE__{} = profile) do
      ExMaude.Pool.child_spec(
        name: profile.pool,
        pool_size: 1,
        pool_max_overflow: 0,
        worker_module: ExMaude.Backend.Port,
        maude_path: profile.binary,
        timeout: profile.limits.deadline_ms,
        max_response_bytes: profile.limits.max_output_bytes
      )
    end

    @doc """
    Verifies one property of one model variant from an abstract initial state.

    Options: `:max_depth`, `:max_solutions`, `:deadline_ms` (each bounded by the
    profile limits) and `:exhaustion` (`true` by default).
    """
    @spec verify(t(), Model.variant(), Serializer.property(), Abstraction.t(), keyword()) ::
            {:ok, Result.t()} | {:error, Error.t()}
    def verify(%__MODULE__{} = profile, variant, property, initial, opts \\ [])
        when is_list(opts) do
      with {:ok, module} <- module(profile.model, variant),
           {:ok, bounds} <- bounds(profile.limits, opts),
           {:ok, initial_term} <- Serializer.term(initial),
           {:ok, command} <-
             Serializer.search(module, initial_term, property,
               max_solutions: bounds.max_solutions,
               max_depth: bounds.max_depth
             ),
           {:ok, load} <- Serializer.load(profile.model.path) do
        base = %Result{
          status: :error,
          property: property,
          variant: variant,
          model: %{id: profile.model.id, digest: profile.model.digest, module: module},
          abstraction_digest: Digest.bytes(Abstraction.module_info(:md5)),
          input_digest: Digest.bytes(initial_term),
          query_digest: Digest.bytes(command),
          engine: profile.engine,
          bounds: bounds
        }

        metadata = %{profile: :formal, operation: property, outcome: :ok}

        started = System.monotonic_time(:millisecond)

        outcome =
          Telemetry.span(:formal, :verification, metadata, fn ->
            run(
              profile,
              base,
              load,
              command,
              module,
              initial_term,
              property,
              Keyword.get(opts, :exhaustion, true)
            )
          end)

        elapsed = System.monotonic_time(:millisecond) - started
        budget = %{budget_used: elapsed / bounds.deadline_ms}

        Telemetry.event(
          :formal,
          :verification,
          budget,
          Map.put(metadata, :outcome, status(outcome))
        )

        outcome
      end
    end

    defp run(profile, base, load, command, module, initial_term, property, exhaustion?) do
      session = %{
        base: base,
        load: load,
        command: command,
        module: module,
        initial_term: initial_term,
        property: property,
        deadline: System.monotonic_time(:millisecond) + base.bounds.deadline_ms,
        ceiling: base.bounds.max_output_bytes,
        exhaustion?: exhaustion?
      }

      outcome =
        ExMaude.Pool.transaction(
          fn worker ->
            os_pids = os_pids(worker)
            {Search.run(session, &execute(worker, &1, &2)), worker, os_pids}
          end,
          pool: profile.pool,
          checkout_timeout: max(session.deadline - System.monotonic_time(:millisecond), 1)
        )

      {outcome, reaped} = reap(outcome)
      {:ok, Search.conclude(outcome, base, reaped)}
    end

    defp status({:ok, %Result{status: status}}), do: status
    defp status({:error, %Error{code: code}}), do: code
    defp status(_outcome), do: :error

    defp execute(worker, command, timeout) do
      case ExMaude.Server.execute(worker, command, timeout: timeout) do
        {:ok, output} ->
          {:ok, output}

        {:error, %ExMaude.Error{type: :timeout, message: message}} ->
          {:error, {:engine_timeout, message}}

        {:error, %ExMaude.Error{type: type}} ->
          {:error, {:engine_error, type}}

        {:error, other} ->
          {:error, other}
      end
    end

    # ex_maude replies with a timeout and then stops the worker; the stop is
    # awaited briefly so the engine behind a stopped worker is always reaped.
    defp reap({result, worker, os_pids}) do
      cond do
        Search.timed_out?(result) ->
          monitor = Process.monitor(worker)

          receive do
            {:DOWN, ^monitor, :process, ^worker, _reason} -> {result, kill_alive(os_pids)}
          after
            @reap_grace_ms ->
              Process.demonitor(monitor, [:flush])
              {result, kill_alive(os_pids)}
          end

        Process.alive?(worker) ->
          {result, 0}

        true ->
          {result, kill_alive(os_pids)}
      end
    end

    defp reap({:error, %ExMaude.Error{type: :timeout, message: message}}),
      do: {{:error, {:engine_timeout, message}}, 0}

    defp reap({:error, %ExMaude.Error{type: type}}), do: {{:error, {:engine_error, type}}, 0}
    defp reap(other), do: {other, 0}

    @doc """
    Removes a pool through its owner and kills any Maude process that survives.

    `terminate` is the caller's own removal, for example
    `fn -> Wotex.Lab.stop_child(lab, :sessions, pool) end`, so the owning
    supervisor does not restart the pool. Returns the number of operating-system
    processes that needed a signal after the grace period.
    """
    @spec stop(t(), pid(), (-> term()), keyword()) :: %{reaped: non_neg_integer()}
    def stop(%__MODULE__{}, pool, terminate, opts \\ [])
        when is_pid(pool) and is_function(terminate, 0) do
      grace = Keyword.get(opts, :grace_ms, 200)
      workers = pool |> linked() |> Enum.flat_map(&linked/1) |> Enum.filter(&Process.alive?/1)
      os_pids = Enum.flat_map(workers, &os_pids/1)
      terminate.()
      Process.sleep(grace)
      %{reaped: kill_alive(os_pids)}
    end

    defp linked(pid) do
      case Process.info(pid, :links) do
        {:links, links} -> Enum.filter(links, &is_pid/1)
        nil -> []
      end
    end

    # Public port introspection only: the ports connected to the worker and their
    # operating-system process ids.
    defp os_pids(worker) do
      for port <- :erlang.ports(),
          Port.info(port, :connected) == {:connected, worker},
          {:os_pid, os_pid} when is_integer(os_pid) <- [Port.info(port, :os_pid)],
          do: os_pid
    end

    defp kill_alive(os_pids) do
      os_pids
      |> Enum.filter(fn os_pid ->
        match?(
          {_out, 0},
          System.cmd("kill", ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true)
        )
      end)
      |> Enum.map(fn os_pid ->
        System.cmd("kill", ["-KILL", Integer.to_string(os_pid)], stderr_to_stdout: true)
      end)
      |> length()
    end

    defp module(model, variant) do
      case Map.fetch(model.modules, variant) do
        {:ok, module} when is_binary(module) ->
          {:ok, module}

        _other ->
          {:error,
           Error.new(:unknown_variant, :admission, "model has no such variant",
             details: %{variant: variant}
           )}
      end
    end

    defp bounds(limits, opts) do
      requested = %{
        max_depth: Keyword.get(opts, :max_depth, limits.max_depth),
        max_solutions: Keyword.get(opts, :max_solutions, limits.max_solutions),
        deadline_ms: Keyword.get(opts, :deadline_ms, limits.deadline_ms),
        max_output_bytes: limits.max_output_bytes
      }

      Enum.reduce_while(requested, {:ok, requested}, fn {key, value}, acc ->
        if is_integer(value) and value >= 1 and value <= Map.fetch!(limits, key),
          do: {:cont, acc},
          else:
            {:halt,
             {:error,
              Error.new(
                :bound_exceeded,
                :admission,
                "verification bound is outside the profile limit",
                details: %{bound: key, value: value}
              )}}
      end)
    end

    defp pool(name) when is_atom(name) and not is_nil(name), do: {:ok, name}

    defp pool(_name),
      do: {:error, Error.new(:invalid_pool, :admission, "an explicit pool name atom is required")}

    defp limits(overrides) when is_map(overrides) do
      merged = Map.merge(@default_limits, Map.take(overrides, Map.keys(@default_limits)))

      Enum.reduce_while(merged, {:ok, merged}, fn {key, value}, acc ->
        if is_integer(value) and value >= 1 and value <= Map.fetch!(@ceilings, key),
          do: {:cont, acc},
          else:
            {:halt,
             {:error,
              Error.new(:limit_exceeded, :admission, "profile limit is outside its hard ceiling",
                details: %{limit: key, value: value}
              )}}
      end)
    end

    defp limits(_overrides),
      do: {:error, Error.new(:invalid_limits, :admission, "limits must be a map")}

    defp binary(path, expected) when is_binary(path) and is_binary(expected) do
      with :ok <- executable(path),
           {:ok, actual} <- Digest.file(path) do
        if actual == expected,
          do: {:ok, path, actual},
          else:
            {:error,
             Error.new(
               :unsupported,
               :admission,
               "executable digest does not match the pinned digest",
               details: %{expected: expected, actual: actual}
             )}
      end
    end

    defp binary(_path, _expected),
      do:
        {:error,
         Error.new(
           :unsupported,
           :admission,
           "an explicit executable path and pinned sha256 digest are required"
         )}

    defp executable(path) do
      case File.stat(path) do
        {:ok, %File.Stat{type: :regular, mode: mode}} when Bitwise.band(mode, 0o111) != 0 ->
          :ok

        {:ok, _stat} ->
          {:error, Error.new(:unsupported, :admission, "executable path is not an executable file")}

        {:error, reason} ->
          {:error,
           Error.new(:unsupported, :admission, "executable is unavailable",
             details: %{reason: reason}
           )}
      end
    end

    defp engine_version(binary) do
      task = Task.async(fn -> System.cmd(binary, ["--version"], stderr_to_stdout: true) end)

      case Task.yield(task, @version_timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, {output, 0}} ->
          case Regex.run(~r/\A\s*(\d+\.\d+(?:\.\d+)?)\s*\z/, output) do
            [_all, version] ->
              {:ok, version}

            nil ->
              {:error,
               Error.new(:unsupported, :admission, "executable did not report a Maude version")}
          end

        _other ->
          {:error, Error.new(:unsupported, :admission, "executable cannot run on this platform")}
      end
    end

    defp ex_maude_version do
      case Application.spec(:ex_maude, :vsn) do
        nil -> "unknown"
        vsn -> List.to_string(vsn)
      end
    end
  end
end

# coveralls-ignore-stop
