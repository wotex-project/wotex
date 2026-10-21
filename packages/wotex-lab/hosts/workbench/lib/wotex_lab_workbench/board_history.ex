defmodule WotexLabWorkbench.BoardHistory do
  @moduledoc """
  Refreshes at most sixteen existing pin definitions within a shared 1.5-second
  budget. Each group retains the room binding and closed history ranges. The
  caller owns task startup, cancellation and session revalidation before use.
  """

  alias WotexLabWorkbench.HistoryPanels

  @doc "Loads pin groups in a rotating deterministic range order."
  @spec load(map(), [map()], non_neg_integer()) :: [map() | {:unavailable, [String.t()], integer()}]
  def load(binding, pins, rotation \\ 0) do
    groups =
      pins
      |> Enum.take(16)
      |> Enum.group_by(& &1.range)
      |> Enum.sort()

    offset = if groups == [], do: 0, else: rem(rotation, length(groups))
    {before, after_offset} = Enum.split(groups, offset)
    deadline = System.monotonic_time(:millisecond) + 1_500

    Enum.flat_map(after_offset ++ before, fn {range, selected} ->
      budget = max(deadline - System.monotonic_time(:millisecond), 0)

      case HistoryPanels.load(binding, Enum.uniq(Enum.map(selected, & &1.metric)), range,
             budget_ms: budget
           ) do
        {:ok, result} ->
          [Map.put(result, :queried_at, System.system_time(:millisecond))]

        {:error, _} ->
          [{:unavailable, Enum.map(selected, & &1.id), System.system_time(:millisecond)}]
      end
    end)
  end
end
