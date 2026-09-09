defmodule Wotex.Conformance.FailingTarget do
  @moduledoc false

  @behaviour Wotex.Conformance.Target

  @impl true
  def artifact_path(%{failure: :artifact}), do: raise("synthetic callback failure")
  def artifact_path(%{failure: :artifact_throw}), do: throw(:synthetic_callback_failure)
  def artifact_path(%{artifact_result: result}), do: result
  def artifact_path(%{artifact_path: path}), do: {:ok, path}

  @impl true
  def invoke(%{failure: :invoke}, _), do: raise("synthetic callback failure")
  def invoke(%{failure: :invoke_throw}, _), do: throw(:synthetic_callback_failure)
  def invoke(%{invoke_result: result}, _), do: result
end
