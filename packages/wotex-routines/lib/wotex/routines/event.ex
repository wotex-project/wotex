defmodule Wotex.Routines.Event do
  @moduledoc "Explicit original trigger or consumer receipt. Data does not authenticate a transaction or report."

  alias Wotex.Routines.{Error, Limits, Validation}

  @common ~w(kind original program_digest)
  @due ~w(schedule_id due_ms late_window_ms clock_generation time_zone_basis)
  @stages ~w(local_queue protocol_response correlated_report reported_match)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Validates a closed event against its original/program and kind-specific shape."
  @spec new(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <- Validation.fields(data, @common, fields(data), "/event"),
         :ok <- Validation.text(data["original"], "/event/original"),
         :ok <- Validation.digest(data["program_digest"], "/event/program_digest"),
         :ok <- event(data, limits) do
      {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Revalidates an event before projecting complete data."
  @spec to_map(term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(event, limits) do
    with {:ok, event} <- new(event, limits), do: {:ok, event.data}
  end

  defp fields(%{"kind" => kind}) when kind in ~w(manual cancel), do: []
  defp fields(%{"kind" => "due"}), do: @due
  defp fields(%{"kind" => "fact"}), do: ~w(binding fact_id)
  defp fields(%{"kind" => "admission"}), do: ~w(path ref outcome)
  defp fields(%{"kind" => "handoff"}), do: ~w(path ref)
  defp fields(%{"kind" => "result"}), do: ~w(path ref stage outcome report_contract)
  defp fields(_), do: []

  defp event(%{"kind" => kind} = data, _) when kind in ~w(manual cancel),
    do: Validation.fields(data, @common)

  defp event(%{"kind" => "due"} = data, limits) do
    with :ok <- Validation.fields(data, @common ++ @due),
         :ok <- Validation.text(data["schedule_id"], "/event/schedule_id"),
         :ok <- Validation.integer(data["due_ms"], limits, "/event/due_ms"),
         :ok <- Validation.integer(data["late_window_ms"], limits, "/event/late_window_ms", 1),
         :ok <- Validation.text(data["clock_generation"], "/event/clock_generation"),
         :ok <- Validation.integer(data["due_ms"] + data["late_window_ms"], limits, "/event/window") do
      Validation.digest(data["time_zone_basis"], "/event/time_zone_basis")
    end
  end

  defp event(%{"kind" => "fact"} = data, _) do
    with :ok <- Validation.fields(data, @common ++ ~w(binding fact_id)),
         :ok <- Validation.text(data["binding"], "/event/binding") do
      Validation.text(data["fact_id"], "/event/fact_id")
    end
  end

  defp event(%{"kind" => "admission"} = data, limits) do
    with :ok <- Validation.fields(data, @common ++ ~w(path ref outcome)),
         :ok <- receipt(data, limits) do
      Validation.choice(data["outcome"], ~w(held refused), "/event/outcome")
    end
  end

  defp event(%{"kind" => "handoff"} = data, limits) do
    with :ok <- Validation.fields(data, @common ++ ~w(path ref)), do: receipt(data, limits)
  end

  defp event(%{"kind" => "result"} = data, limits) do
    with :ok <- Validation.fields(data, @common ++ ~w(path ref stage outcome report_contract)),
         :ok <- receipt(data, limits),
         :ok <- Validation.choice(data["stage"], @stages, "/event/stage"),
         :ok <- Validation.choice(data["outcome"], ~w(accepted failed unknown), "/event/outcome") do
      report_contract(data)
    end
  end

  defp event(_, _), do: Error.refusal(:unsupported_event, "/event/kind")

  defp receipt(data, limits) do
    with :ok <- Validation.text(data["ref"], "/event/ref"),
         true <- is_list(data["path"]) and length(data["path"]) <= 32 do
      Validation.each(data["path"], &Validation.integer(&1, limits, "/event/path", 0))
    else
      false -> Error.refusal(:invalid_path, "/event/path")
      error -> error
    end
  end

  defp report_contract(%{"stage" => stage, "report_contract" => nil})
       when stage in ~w(local_queue protocol_response), do: :ok

  defp report_contract(%{"stage" => stage, "report_contract" => ref})
       when stage in ~w(correlated_report reported_match) do
    with :ok <- Validation.fields(ref, ~w(id version semantic_digest)),
         :ok <- Validation.text(ref["id"], "/event/report_contract"),
         :ok <- Validation.text(ref["version"], "/event/report_contract") do
      Validation.digest(ref["semantic_digest"], "/event/report_contract")
    end
  end

  defp report_contract(_), do: Error.refusal(:invalid_report_contract, "/event/report_contract")
end
