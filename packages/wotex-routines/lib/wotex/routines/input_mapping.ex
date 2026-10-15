defmodule Wotex.Routines.InputMapping do
  @moduledoc """
  An explicitly installed scalar correspondence from an external profile.

  The consumer qualifies and installs the complete mapping identity. Construction
  checks that identity, current Basis and references; it confers no authority.
  """

  alias Wotex.Routines.{Basis, Error, InputValidation, Limits, Registry, Validation}

  @fields ~w(id version semantic_ref reader_contract_ref compiler_ref legacy_basis_ref basis correspondence_ref projection enum_table channel_id affordance profile_sha256 closure_sha256 capture_digest external_unit observation receipt_clock)
  @dimensions %{
    "temperature" => [0, 0, 0, 0, 1, 0, 0],
    "fraction" => [0, 0, 0, 0, 0, 0, 0],
    "illuminance" => [-2, 0, 0, 0, 0, 0, 1],
    "power" => [2, 1, -3, 0, 0, 0, 0],
    "energy" => [2, 1, -2, 0, 0, 0, 0],
    "time" => [0, 0, 1, 0, 0, 0, 0],
    "electric_potential" => [2, 1, -3, -1, 0, 0, 0]
  }
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Checks the complete mapping, claimed digest and current explicit installation."
  @spec new(term(), Registry.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, registry, limits) do
    with {:ok, data, limits} <- InputValidation.admit(input, limits, __MODULE__),
         :ok <- Validation.fields(data, ["sha256" | @fields]),
         :ok <- InputValidation.digest(data["sha256"], 64, "/sha256"),
         {:ok, digest} <- digest(Map.delete(data, "sha256"), registry, limits),
         true <- digest == data["sha256"],
         :ok <- Registry.require_contract(registry, InputValidation.legacy_ref(data), limits) do
      {:ok, %__MODULE__{data: data}}
    else
      false -> Error.refusal(:stale_basis, "/sha256")
      error -> InputValidation.refusal(error)
    end
  end

  @doc "Computes an unsigned mapping identity after checking its explicit basis and correspondence."
  @spec digest(term(), Registry.t(), Limits.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def digest(input, registry, limits) do
    with {:ok, data, limits} <- InputValidation.admit(input, limits, nil),
         :ok <- Validation.fields(data, @fields),
         :ok <- identity(data),
         :ok <- reader_contract(data),
         {:ok, basis} <- Basis.to_map(data["basis"], registry, limits),
         true <- Map.take(basis, ~w(id version semantic_digest)) == data["legacy_basis_ref"],
         :ok <-
           Registry.require_contract(
             registry,
             InputValidation.legacy_ref(data["correspondence_ref"]),
             limits
           ),
         :ok <- observation(data["observation"]),
         :ok <- channel(data, basis),
         :ok <- clock(data["receipt_clock"], limits),
         :ok <- representation(data, basis),
         {:ok, digest} <- InputValidation.hash("wotex.routines.input-mapping@1", data, limits) do
      {:ok, digest}
    else
      false -> Error.refusal(:stale_basis, "/legacy_basis_ref")
      error -> InputValidation.refusal(error)
    end
  end

  @doc "Validates at most 256 mappings under one aggregate envelope and sorts by identity."
  @spec new_all(term(), Registry.t(), Limits.t()) :: {:ok, [t()]} | {:error, Error.t()}
  def new_all(inputs, registry, limits) do
    with {:ok, data, limits} <- InputValidation.admit(inputs, limits, nil),
         true <- is_list(data),
         :ok <- count(data),
         true <- Enum.all?(data, &(is_map(&1) and not is_struct(&1))) do
      Enum.reduce_while(data, {:ok, []}, fn input, {:ok, values} ->
        case new(input, registry, limits) do
          {:ok, value} -> {:cont, {:ok, [value | values]}}
          error -> {:halt, error}
        end
      end)
      |> unique()
    else
      false -> Error.refusal(:invalid_input)
      error -> InputValidation.refusal(error)
    end
  end

  defp count(data) do
    if length(data) <= 256, do: :ok, else: Error.refusal(:input_limit)
  end

  defp unique({:ok, values}) do
    ids = Enum.map(values, & &1.data["id"])

    if length(Enum.uniq(ids)) == length(ids),
      do: {:ok, Enum.sort_by(values, &{&1.data["id"], &1.data["version"]})},
      else: Error.refusal(:unsupported_mapping, "/id")
  end

  defp unique(error), do: error

  @doc "Revalidates the native mapping before returning its closed data."
  @spec to_map(term(), Registry.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(input, registry, limits) do
    with {:ok, value} <- new(input, registry, limits), do: {:ok, value.data}
  end

  @doc "Revalidates and returns the external-shape mapping reference."
  @spec reference(term(), Registry.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def reference(input, registry, limits) do
    with {:ok, data} <- to_map(input, registry, limits),
         do: {:ok, Map.take(data, ~w(id version sha256))}
  end

  defp identity(data) do
    with :ok <-
           InputValidation.external_ref(
             Map.take(data, ~w(id version)) |> Map.put("sha256", String.duplicate("0", 64)),
             "/id"
           ),
         :ok <-
           Validation.each(
             ~w(semantic_ref reader_contract_ref compiler_ref correspondence_ref),
             &InputValidation.external_ref(data[&1], "/" <> &1)
           ),
         do:
           Validation.each(
             ~w(profile_sha256 closure_sha256 capture_digest),
             &InputValidation.digest(data[&1], 64, "/" <> &1)
           )
  end

  defp reader_contract(data) do
    case InputValidation.reader(Wotex.Profiles.Proposal, :identity, []) do
      %{} = ref ->
        if ref == data["reader_contract_ref"],
          do: :ok,
          else: Error.refusal(:stale_basis, "/reader_contract_ref")

      error ->
        error
    end
  end

  defp channel(data, basis) do
    with :ok <- InputValidation.key(data["channel_id"], "/channel_id"),
         :ok <- Validation.fields(data["affordance"], ~w(kind name)),
         :ok <- InputValidation.key(data["affordance"]["name"], "/affordance/name") do
      if data["affordance"]["kind"] in ~w(property event) and
           data["affordance"]["kind"] == basis["affordance"]["type"] and
           data["affordance"]["name"] == basis["affordance"]["name"] and
           basis["affordance"]["operation"] in ~w(readproperty observeproperty subscribeevent) and
           basis["effects"]["resource_roles"] == [] and
           data["observation"]["source_class"] in basis["evidence"]["sources"],
         do: :ok,
         else: Error.refusal(:unsupported_mapping, "/affordance")
    end
  end

  defp observation(data) do
    with :ok <- Validation.fields(data, ~w(source_ref source_epoch source_class source_time_basis)),
         :ok <- InputValidation.text(data["source_ref"], 128, "/observation/source_ref"),
         :ok <- InputValidation.digest(data["source_epoch"], 32, "/observation/source_epoch"),
         :ok <-
           Validation.choice(
             data["source_class"],
             ~w(device_report derived_report protocol_response),
             "/observation/source_class"
           ),
         do: optional_basis(data["source_time_basis"])
  end

  defp optional_basis(nil), do: :ok
  defp optional_basis(value), do: Validation.digest(value, "/observation/source_time_basis")

  defp clock(%{"format" => "wotex.routines.receipt-clock@1"} = data, limits) do
    with :ok <-
           Validation.fields(
             data,
             ~w(format projection source_epoch source_origin_us target_epoch target_origin_ms)
           ),
         :ok <-
           Validation.choice(data["projection"], ["floor_millisecond"], "/receipt_clock/projection"),
         :ok <-
           InputValidation.text(
             data["target_epoch"],
             limits.data["max_string_bytes"],
             "/receipt_clock/target_epoch"
           ) do
      clock(Map.drop(data, ~w(format projection)), limits)
    end
  end

  defp clock(data, limits) do
    with :ok <-
           Validation.fields(data, ~w(source_epoch source_origin_us target_epoch target_origin_ms)),
         :ok <- InputValidation.digest(data["source_epoch"], 32, "/receipt_clock/source_epoch"),
         {:ok, _} <-
           InputValidation.signed(data["source_origin_us"], "/receipt_clock/source_origin_us"),
         :ok <- Validation.text(data["target_epoch"], "/receipt_clock/target_epoch"),
         do:
           Validation.integer(
             data["target_origin_ms"],
             limits,
             "/receipt_clock/target_origin_ms",
             0
           )
  end

  defp representation(%{"projection" => "exact_integer", "enum_table" => nil} = data, %{
         "value" => %{"type" => "integer", "unit" => unit}
       }) do
    with :ok <- external_unit(data["external_unit"]) do
      if data["external_unit"]["dimension"] == @dimensions[unit["dimension"]],
        do: :ok,
        else: Error.refusal(:incompatible_dimension, "/external_unit/dimension")
    end
  end

  defp representation(%{"projection" => "boolean", "enum_table" => nil, "external_unit" => nil}, %{
         "value" => %{"type" => "boolean"}
       }) do
    :ok
  end

  defp representation(%{"projection" => "enum", "external_unit" => nil} = data, %{
         "value" => %{"type" => "enum", "enum" => alternatives}
       }) do
    entries = data["enum_table"]

    with true <- is_list(entries) and length(entries) in 1..256,
         :ok <- Validation.each(entries, &entry/1),
         sources = Enum.map(entries, & &1["source"]),
         targets = Enum.map(entries, & &1["target"]),
         true <-
           sources == Enum.sort(Enum.uniq(sources)) and
             Enum.sort(targets) == Enum.sort(alternatives),
         do: :ok,
         else: (_ -> Error.refusal(:unsupported_mapping, "/enum_table"))
  end

  defp representation(_, _), do: Error.refusal(:unsupported_mapping, "/projection")

  defp entry(data) do
    with :ok <- Validation.fields(data, ~w(source target)),
         :ok <- InputValidation.text(data["source"], 128, "/enum_table/source"),
         do: InputValidation.text(data["target"], 128, "/enum_table/target")
  end

  defp external_unit(data) do
    with :ok <-
           Validation.fields(data, ~w(quantity_kind dimension scale_n scale_d offset_n offset_d)),
         :ok <- InputValidation.text(data["quantity_kind"], 256, "/external_unit/quantity_kind"),
         :ok <- Validation.iri(data["quantity_kind"], "/external_unit/quantity_kind"),
         true <- is_list(data["dimension"]) and length(data["dimension"]) == 7,
         true <- Enum.all?(data["dimension"], &(is_integer(&1) and &1 in -32..32)),
         :ok <- rational(data, "scale", true),
         :ok <- rational(data, "offset", false),
         do: :ok,
         else: (_ -> Error.refusal(:invalid_input, "/external_unit"))
  end

  defp rational(data, key, positive) do
    with {:ok, n} <- InputValidation.signed(data[key <> "_n"], "/external_unit"),
         {:ok, d} <- InputValidation.signed(data[key <> "_d"], "/external_unit"),
         true <- d > 0 and (not positive or n > 0) and Integer.gcd(n, d) == 1,
         do: :ok,
         else: (_ -> Error.refusal(:invalid_input, "/external_unit"))
  end
end
