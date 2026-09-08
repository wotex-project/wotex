defmodule Wotex.Lab.Test.CookbookRunner do
  @moduledoc false

  # Evaluates a cookbook's Elixir cells in order, the way Livebook's evaluator
  # does: one binding and one `Macro.Env` threaded through every cell, so
  # aliases and variables defined in one cell are visible in the next. The
  # `Mix.install/1` cell is skipped explicitly; artifact installation belongs
  # to Livebook, never to the test suite. Evaluation runs in an unlinked task
  # bounded by the notebook's declared timeout. When the last cell has run,
  # every process still linked to the evaluator is signalled and counted as a
  # leak. Bindings grant no cleanup authority: notebooks explicitly stop their
  # own resources. This source-only helper is not a sandbox or a proof that
  # unlinked processes, telemetry handlers or timeout resources were reclaimed.

  alias Wotex.Lab.Cookbook

  @type outcome :: %{
          result: term(),
          binding: keyword(),
          cells: non_neg_integer(),
          modules: [module()],
          leaked: non_neg_integer()
        }

  @spec run(String.t(), keyword()) :: {:ok, outcome()} | {:error, map()}
  def run(id, opts \\ []) do
    with {:ok, entry} <- Cookbook.fetch(id),
         {:ok, source} <- Cookbook.read(id) do
      cells = Cookbook.cells(source)
      timeout = Keyword.get(opts, :timeout, entry.timeout_ms)
      seed = Keyword.get(opts, :binding, [])
      {:ok, supervisor} = Task.Supervisor.start_link()

      task =
        Task.Supervisor.async_nolink(supervisor, fn ->
          evaluate(entry, cells, seed, supervisor)
        end)

      outcome =
        case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
          {:ok, outcome} -> outcome
          {:exit, reason} -> {:error, %{cell: nil, kind: :exit, reason: reason}}
          nil -> {:error, %{cell: nil, kind: :timeout, reason: timeout}}
        end

      Supervisor.stop(supervisor)
      outcome
    end
  end

  @spec install_cell?(binary()) :: boolean()
  def install_cell?(cell), do: String.starts_with?(String.trim_leading(cell), "Mix.install(")

  defp evaluate(entry, cells, seed, supervisor) do
    env = Code.env_for_eval(file: entry.path)
    runnable = Enum.reject(cells, &install_cell?/1)

    outcome =
      runnable
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, nil, seed, env}, fn {cell, index}, {:ok, _last, binding, env} ->
        case eval_cell(cell, index, binding, env) do
          {:ok, value, binding, env} -> {:cont, {:ok, value, binding, env}}
          {:error, failure} -> {:halt, {:error, failure}}
        end
      end)

    case outcome do
      {:ok, value, binding, env} ->
        {:ok,
         %{
           result: value,
           binding: binding,
           cells: length(runnable),
           modules: modules(runnable, env),
           leaked: sweep(supervisor)
         }}

      {:error, failure} ->
        _leaked = sweep(supervisor)
        {:error, failure}
    end
  end

  defp eval_cell(cell, index, binding, env) do
    quoted = Code.string_to_quoted!(cell, file: env.file, line: 1)
    {value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)
    {:ok, value, binding, env}
  catch
    kind, reason ->
      {:error, %{cell: index, kind: kind, reason: reason, stacktrace: __STACKTRACE__}}
  end

  defp sweep(supervisor) do
    {:links, links} = Process.info(self(), :links)
    leaked = for pid <- links, is_pid(pid), pid != supervisor, do: pid
    Enum.each(leaked, &Process.exit(&1, :shutdown))
    length(leaked)
  end

  defp modules(cells, env) do
    cells
    |> Enum.flat_map(fn cell ->
      cell
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        # `alias A.B.{C, D}`: the prefix is a namespace, not a module.
        {{:., _dot, [_prefix, :{}]}, _meta, children}, acc ->
          {{:__block__, [], children}, acc}

        {:__aliases__, _meta, [first | _rest]} = node, acc when is_atom(first) ->
          {node, [Macro.expand(node, env) | acc]}

        node, acc ->
          {node, acc}
      end)
      |> elem(1)
    end)
    |> Enum.filter(&is_atom/1)
    |> Enum.uniq()
  end
end
