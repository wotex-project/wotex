defmodule Wotex.Routines.Fact do
  @moduledoc "Bounded observation data retaining source and receipt continuity, quality and provenance."

  alias Wotex.Routines.{Error, Limits, Unit, Validation}

  @fields ~w(id thing_id affordance_type affordance_name value unit quality source_class source_id source_epoch
    sequence source_time source_time_trust source_time_basis source_uncertainty_ms received_at receipt_epoch receipt_ms profile_digest replay continuity
    expires_ms derivation_digest contributors)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Validates and normalizes a complete fact without qualifying its source or renewing freshness."
  @spec new(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <- Validation.fields(data, @fields),
         :ok <-
           Validation.each(
             ~w(id affordance_name source_id source_epoch receipt_epoch),
             &Validation.text(data[&1], "/" <> &1)
           ),
         :ok <- Validation.iri(data["thing_id"], "/thing_id"),
         :ok <- Validation.choice(data["affordance_type"], ~w(property event), "/affordance_type"),
         :ok <- Validation.choice(data["quality"], ~w(usable stale invalid unknown), "/quality"),
         :ok <-
           Validation.choice(
             data["source_class"],
             ~w(device_report derived_report protocol_response),
             "/source_class"
           ),
         :ok <- Validation.choice(data["replay"], ~w(fresh retained replayed), "/replay"),
         :ok <- Validation.choice(data["continuity"], ~w(continuous baseline lost), "/continuity"),
         :ok <-
           Validation.each(
             ~w(sequence receipt_ms expires_ms),
             &Validation.integer(data[&1], limits, "/" <> &1, 0)
           ),
         :ok <- Validation.digest(data["profile_digest"], "/profile_digest"),
         :ok <- unit_value(data["unit"], data["value"], data["quality"], limits),
         :ok <- null_quality(data),
         {:ok, source_time} <- source_time(data["source_time"]),
         :ok <- source_clock(data, limits),
         {:ok, received_at} <- Validation.timestamp(data["received_at"], "/received_at"),
         :ok <- expiry(data),
         :ok <- derivation(data, limits) do
      normalized =
        data
        |> Map.put("source_time", source_time)
        |> Map.put("received_at", received_at)

      {:ok, %__MODULE__{data: normalized}}
    end
  end

  @doc "Revalidates and projects every fact member as JSON data."
  @spec to_map(term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value, limits) do
    with {:ok, value} <- new(value, limits), do: {:ok, value.data}
  end

  defp unit_value(nil, _, _, _), do: :ok

  defp unit_value(unit, value, quality, limits) do
    with {:ok, unit} <- Unit.new(unit, limits) do
      if is_nil(value) or quality != "usable" do
        :ok
      else
        case Unit.convert(value, unit, unit, limits) do
          {:ok, _} -> :ok
          error -> error
        end
      end
    end
  end

  defp null_quality(%{"value" => nil, "quality" => "usable"}),
    do: Error.refusal(:invalid_quality, "/quality")

  defp null_quality(_), do: :ok

  defp source_time(nil), do: {:ok, nil}
  defp source_time(time), do: Validation.timestamp(time, "/source_time")

  defp source_clock(data, limits) do
    with :ok <-
           Validation.choice(
             data["source_time_trust"],
             ~w(trusted untrusted unknown),
             "/source_time_trust"
           ),
         :ok <- optional_digest(data["source_time_basis"]),
         :ok <- optional_uncertainty(data["source_uncertainty_ms"], limits) do
      if data["source_time_trust"] != "trusted" or
           (data["source_time"] != nil and data["source_time_basis"] != nil and
              data["source_uncertainty_ms"] != nil),
         do: :ok,
         else: Error.refusal(:missing_clock_basis, "/source_time_trust")
    end
  end

  defp optional_digest(nil), do: :ok
  defp optional_digest(value), do: Validation.digest(value, "/source_time_basis")
  defp optional_uncertainty(nil, _), do: :ok

  defp optional_uncertainty(value, limits),
    do: Validation.integer(value, limits, "/source_uncertainty_ms", 0)

  defp expiry(data) do
    if data["expires_ms"] >= data["receipt_ms"],
      do: :ok,
      else: Error.refusal(:invalid_expiry, "/expires_ms")
  end

  defp derivation(%{"derivation_digest" => nil, "contributors" => [], "source_class" => source}, _)
       when source in ["device_report", "protocol_response"], do: :ok

  defp derivation(data, limits) do
    with :ok <- Validation.choice(data["source_class"], ["derived_report"], "/source_class"),
         :ok <- Validation.digest(data["derivation_digest"], "/derivation_digest"),
         contributors when is_list(contributors) and contributors != [] <- data["contributors"],
         :ok <- Validation.each(contributors, &contributor(&1, data, limits)),
         ids = Enum.map(contributors, & &1["fact_id"]),
         true <- length(Enum.uniq(ids)) == length(ids) do
      :ok
    else
      false -> Error.refusal(:duplicate_identity, "/contributors")
      {:error, _} = error -> error
      _ -> Error.refusal(:invalid_derivation, "/contributors")
    end
  end

  defp contributor(data, fact, limits) do
    with :ok <-
           Validation.fields(
             data,
             ~w(fact_id source_id source_epoch sequence receipt_epoch expires_ms),
             [],
             "/contributors"
           ),
         :ok <-
           Validation.each(
             ~w(fact_id source_id source_epoch receipt_epoch),
             &Validation.text(data[&1], "/contributors/" <> &1)
           ),
         :ok <-
           Validation.each(
             ~w(sequence expires_ms),
             &Validation.integer(data[&1], limits, "/contributors/" <> &1, 0)
           ) do
      if data["receipt_epoch"] == fact["receipt_epoch"] and data["expires_ms"] >= fact["expires_ms"],
        do: :ok,
        else: Error.refusal(:invalid_derivation_basis, "/contributors")
    end
  end
end
