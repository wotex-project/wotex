defmodule Wotex.Lab.Check.ReferenceSummary do
  @moduledoc false

  # Parse exactly one complete terminal ExUnit summary, not arbitrary numbers
  # or a prefix embedded in diagnostic output. An exit code alone is no proof
  # that ExUnit ran any tests.
  def parse(output) when is_binary(output) and byte_size(output) <= 8_388_608 do
    summaries =
      Regex.scan(
        ~r/^(?:Result: (\d{1,9})(?:\/(\d{1,9}))? passed(?:, (\d{1,9}) excluded)?|(\d{1,9}) tests?, (\d{1,9}) failures?(?:, (\d{1,9}) excluded)?)\r?$/m,
        output,
        capture: :all_but_first
      )

    case summaries do
      [fields] -> fields |> pad() |> decode()
      _missing_or_ambiguous -> {:error, :invalid_summary}
    end
  end

  def parse(_output), do: {:error, :invalid_summary}

  def successful?(0, {:ok, %{tests: tests, failures: 0}}) when tests > 0, do: true
  def successful?(_status, _summary), do: false

  defp pad(fields), do: fields ++ List.duplicate("", 6 - length(fields))

  defp decode(["", "", "", total, failed, excluded]),
    do: admit(integer(total) - integer(excluded), integer(failed), integer(excluded))

  defp decode([passed, total, excluded, "", "", ""]) do
    total = if total == "", do: passed, else: total
    admit(integer(total), integer(total) - integer(passed), integer(excluded))
  end

  defp admit(total, failed, excluded)
       when total > 0 and failed >= 0 and failed <= total and excluded >= 0,
       do: {:ok, %{tests: total, failures: failed, excluded: excluded}}

  defp admit(_total, _failed, _excluded), do: {:error, :invalid_summary}

  defp integer(""), do: 0
  defp integer(value), do: String.to_integer(value)
end
