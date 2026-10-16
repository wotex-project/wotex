defmodule Wotex.Routines.Event do
  @moduledoc """
  Explicit triggers, continuation requests and receipts for the pure kernel.

  `Wotex.Routines.Event.new/2` takes a plain string-keyed event map or an
  existing Event value, with explicit `Wotex.Routines.Limits`. Every event
  requires `"kind"`, a nonempty `"original"` identity and a
  `"program_digest"` in `sha256:` form. Success is
  `{:ok, event}` with a `t:Wotex.Routines.Event.t/0`; malformed, unsupported or
  over-bound data returns `{:error, error}` with a `Wotex.Routines.Error`.
  `Wotex.Routines.Event.to_map/2` repeats validation before returning
  `{:ok, data}`. Unknown fields are refused.

  A `"manual"` trigger, `"cancel"` or `"resume"` event has only those three
  members. Use `"resume"` to reevaluate an existing original with current
  snapshot/time inputs, without supplying a new trigger, Fact, path or clock
  coordinate. `Wotex.Routines.Kernel.advance/7` requires the exact retained Run
  in prior `"original"`; constructing a resume does not establish that history.
  Resume preserves the reported-edge baseline and cannot create a new run.

  `"due"` adds the immutable UTC schedule/window coordinates; `"elapsed_due"`
  adds the original elapsed schedule/window coordinates and clock basis.
  `"fact"` names a binding and Fact ID for actual reported-edge evaluation.
  The caller supplies the matching qualified snapshot separately to
  `Wotex.Routines.Kernel.advance/7`.

  `"admission"`, `"handoff"` and `"result"` carry a compiled step path and
  receipt reference. Admission records `"held"` or `"refused"`; result records
  an `"accepted"`, `"failed"` or `"unknown"` outcome at its explicit receipt
  stage. Correlated-report and reported-match stages require the installed
  report-contract identity; queue and protocol-response stages require an
  explicit `nil` report contract. Construction checks shape and bounds; the
  kernel checks correspondence with the retained run and installed program.

  A `"satisfied"` event has exactly `"kind"`, `"original"`,
  `"program_digest"`, `"path"`, `"ref"`, `"fact_id"` and `"report_contract"`.
  The path contains at most 32 nonnegative indices; the reference and Fact ID
  are nonempty text. The report contract contains exactly `"id"`, `"version"`
  and `"semantic_digest"`. Supply this event with the existing original and a
  current qualified snapshot to `Wotex.Routines.Kernel.advance/7`. The kernel
  accepts fresh satisfaction only for an eligible unsent absolute Property
  write requiring a reported match, whose exact Fact value equals its compiled
  input. This records current-state completion without a transport handoff or
  a claim that this request caused the report. Construction authenticates
  neither the Fact nor the consumer receipt.

  The consumer owns original identities, authentic receipts, observations,
  persistence and physical handoff. These values authenticate no transaction
  or report, read no clock, and perform no effect.
  """

  alias Wotex.Routines.{Error, Limits, Validation}

  @common ~w(kind original program_digest)
  @due ~w(schedule_id schedule_basis due_ms late_window_ms clock_generation time_zone_basis)
  @elapsed ~w(schedule_id schedule_basis due_elapsed_ms late_window_ms epoch clock_generation time_basis)
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

  defp fields(%{"kind" => kind}) when kind in ~w(manual cancel resume), do: []
  defp fields(%{"kind" => "due"}), do: @due
  defp fields(%{"kind" => "elapsed_due"}), do: @elapsed
  defp fields(%{"kind" => "fact"}), do: ~w(binding fact_id)
  defp fields(%{"kind" => "admission"}), do: ~w(path ref outcome)
  defp fields(%{"kind" => "handoff"}), do: ~w(path ref)
  defp fields(%{"kind" => "result"}), do: ~w(path ref stage outcome report_contract)
  defp fields(%{"kind" => "satisfied"}), do: ~w(path ref fact_id report_contract)
  defp fields(_), do: []

  defp event(%{"kind" => kind} = data, _) when kind in ~w(manual cancel resume),
    do: Validation.fields(data, @common)

  defp event(%{"kind" => "due"} = data, limits) do
    with :ok <- Validation.fields(data, @common ++ @due),
         :ok <- Validation.text(data["schedule_id"], "/event/schedule_id"),
         :ok <- Validation.digest(data["schedule_basis"], "/event/schedule_basis"),
         :ok <- Validation.integer(data["due_ms"], limits, "/event/due_ms"),
         :ok <- Validation.integer(data["late_window_ms"], limits, "/event/late_window_ms", 1),
         :ok <- Validation.text(data["clock_generation"], "/event/clock_generation"),
         :ok <- Validation.integer(data["due_ms"] + data["late_window_ms"], limits, "/event/window") do
      Validation.digest(data["time_zone_basis"], "/event/time_zone_basis")
    end
  end

  defp event(%{"kind" => "elapsed_due"} = data, limits) do
    with :ok <- Validation.fields(data, @common ++ @elapsed),
         :ok <- Validation.text(data["schedule_id"], "/event/schedule_id"),
         :ok <- Validation.digest(data["schedule_basis"], "/event/schedule_basis"),
         :ok <- Validation.integer(data["due_elapsed_ms"], limits, "/event/due_elapsed_ms", 0),
         :ok <- Validation.integer(data["late_window_ms"], limits, "/event/late_window_ms", 1),
         :ok <-
           Validation.integer(
             data["due_elapsed_ms"] + data["late_window_ms"],
             limits,
             "/event/window"
           ),
         :ok <- Validation.text(data["epoch"], "/event/epoch"),
         :ok <- Validation.text(data["clock_generation"], "/event/clock_generation") do
      Validation.digest(data["time_basis"], "/event/time_basis")
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

  defp event(%{"kind" => "satisfied"} = data, limits) do
    with :ok <- Validation.fields(data, @common ++ ~w(path ref fact_id report_contract)),
         :ok <- receipt(data, limits),
         :ok <- Validation.text(data["fact_id"], "/event/fact_id") do
      installed_report_contract(data["report_contract"])
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
       when stage in ~w(correlated_report reported_match), do: installed_report_contract(ref)

  defp report_contract(_), do: Error.refusal(:invalid_report_contract, "/event/report_contract")

  defp installed_report_contract(ref) do
    with :ok <- Validation.fields(ref, ~w(id version semantic_digest)),
         :ok <- Validation.text(ref["id"], "/event/report_contract"),
         :ok <- Validation.text(ref["version"], "/event/report_contract") do
      Validation.digest(ref["semantic_digest"], "/event/report_contract")
    end
  end
end
