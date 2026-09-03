defmodule Wotex.Conformance.Target do
  @moduledoc """
  Behavior for caller-supplied target adapters.

  Production subjects should normally use `Wotex.Conformance.Target.External`,
  which keeps subject code outside this application's dependency graph and VM.
  A custom adapter is represented as `{module, state}` and is owned by the
  consumer.
  """

  alias Wotex.Conformance.{Error, Target.Response}

  @type state :: term()
  @type target :: {module(), state()}

  @doc "Returns the immutable subject archive path owned by the target state."
  @callback artifact_path(state()) :: {:ok, Path.t()} | {:error, Error.t()}

  @doc "Invokes one vector request and reports the measured duration in microseconds."
  @callback invoke(state(), map()) ::
              {:ok, Response.t(), non_neg_integer()}
              | {:error, Error.t(), non_neg_integer()}

  @doc "Normalizes a target struct or `{module, state}` callback tuple."
  @spec normalize(term()) :: {:ok, target()} | {:error, Error.t()}
  def normalize(%{__struct__: module} = target) when is_atom(module) do
    normalize({module, target})
  end

  def normalize({module, state}) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :artifact_path, 1) and
         function_exported?(module, :invoke, 2) do
      {:ok, {module, state}}
    else
      {:error,
       Error.new(:invalid_target, "target module does not implement the required callbacks")}
    end
  end

  def normalize(_target),
    do: {:error, Error.new(:invalid_target, "target must be an external target or callback tuple")}

  @doc "Calls the target's archive-path callback and validates its result."
  @spec artifact_path(target()) :: {:ok, Path.t()} | {:error, Error.t()}
  def artifact_path({module, state}) do
    case safely(fn -> module.artifact_path(state) end, :target_artifact_callback_failed) do
      {:ok, path} when is_binary(path) and path != "" ->
        {:ok, path}

      {:error, %Error{} = error} ->
        {:error, error}

      _result ->
        {:error,
         Error.new(:invalid_target_callback, "target artifact callback returned an invalid result")}
    end
  end

  @doc "Calls the target for one request and validates its response and duration."
  @spec invoke(target(), map()) ::
          {:ok, Response.t(), non_neg_integer()}
          | {:error, Error.t(), non_neg_integer()}
  def invoke({module, state}, request) do
    case safely(fn -> module.invoke(state, request) end, :target_callback_failed) do
      {:ok, %Response{} = response, duration_us}
      when is_integer(duration_us) and duration_us >= 0 ->
        {:ok, response, duration_us}

      {:error, %Error{} = error, duration_us}
      when is_integer(duration_us) and duration_us >= 0 ->
        {:error, error, duration_us}

      {:error, %Error{} = error} ->
        {:error, error, 0}

      _result ->
        {:error, Error.new(:invalid_target_callback, "target callback returned an invalid result"),
         0}
    end
  end

  defp safely(callback, code) do
    callback.()
  rescue
    _exception -> {:error, Error.new(code, "target callback failed")}
  catch
    _kind, _reason -> {:error, Error.new(code, "target callback failed")}
  end
end
