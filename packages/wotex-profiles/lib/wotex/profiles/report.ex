defmodule Wotex.Profiles.Report do
  @moduledoc false

  alias Wotex.Profiles.{Error, Grammar, Numeric}

  @fields ~w(channel_id profile_sha256 binding capture_epoch source_ref source_epoch sequence source_time receipt_time continuity quality quality_reason value)
  @reasons [nil | ~w(missing device_invalid profile_sentinel source_gap stale unsupported)]

  @doc false
  @spec header(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def header(data, limits) do
    with {:ok, data, _} <- Grammar.admit(data, limits),
         :ok <- Grammar.fields(data, @fields, "/report"),
         :ok <- Grammar.key(data["channel_id"], "/report/channel_id"),
         :ok <- Grammar.digest(data["profile_sha256"], "/report/profile_sha256"),
         :ok <- Grammar.reference(data["binding"], "/report/binding"),
         :ok <- epoch(data["capture_epoch"], "/report/capture_epoch"),
         :ok <- Grammar.text(data["source_ref"], 128, "/report/source_ref"),
         :ok <- epoch(data["source_epoch"], "/report/source_epoch"),
         :ok <- optional_uint(data["sequence"], "/report/sequence"),
         :ok <- source_time(data["source_time"]),
         :ok <- receipt_time(data["receipt_time"]),
         true <- data["continuity"] in ~w(unknown baseline continuous gap retained replayed),
         true <- data["quality"] in ~w(usable invalid unknown stale),
         true <- data["quality_reason"] in @reasons,
         true <- data["quality"] != "usable" or data["quality_reason"] == nil do
      {:ok, data}
    else
      false -> Error.refusal(:invalid_input, "/report")
      error -> error
    end
  end

  defp epoch(value, path) do
    if is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value),
      do: :ok,
      else: Error.refusal(:invalid_input, path)
  end

  defp optional_uint(nil, _), do: :ok

  defp optional_uint(value, path) do
    case Numeric.integer(value, 0, 18_446_744_073_709_551_615, path) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp source_time(nil), do: :ok

  defp source_time(data) do
    with :ok <- Grammar.fields(data, ~w(utc trust uncertainty_us), "/report/source_time"),
         :ok <- utc(data["utc"]),
         true <- data["trust"] in ~w(trusted untrusted unknown),
         :ok <- optional_uint(data["uncertainty_us"], "/report/source_time/uncertainty_us"),
         true <- data["trust"] != "trusted" or data["uncertainty_us"] != nil do
      :ok
    else
      false -> Error.refusal(:invalid_input, "/report/source_time")
      error -> error
    end
  end

  defp utc(value) when is_binary(value) and byte_size(value) <= 35 do
    with true <-
           Regex.match?(
             ~r/\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?(?:Z|\+00:00)\z/,
             value
           ),
         {:ok, %DateTime{year: year}, 0} when year in 0..9999 <- DateTime.from_iso8601(value) do
      :ok
    else
      _ -> Error.refusal(:invalid_input, "/report/source_time/utc")
    end
  end

  defp utc(_), do: Error.refusal(:invalid_input, "/report/source_time/utc")

  defp receipt_time(data) do
    with :ok <- Grammar.fields(data, ~w(epoch monotonic_us), "/report/receipt_time"),
         :ok <- epoch(data["epoch"], "/report/receipt_time/epoch"),
         {:ok, _} <-
           Numeric.integer(
             data["monotonic_us"],
             -9_223_372_036_854_775_808,
             9_223_372_036_854_775_807,
             "/report/receipt_time/monotonic_us"
           ),
         do: :ok
  end
end
