defmodule Wotex.Routines.InputValidation do
  @moduledoc false

  alias Wotex.Routines.{Error, Limits, Validation}

  @path_fields ~w(proposal metadata id version sha256 semantic semantic_ref reader_contract_ref compiler_ref
    legacy_basis_ref basis correspondence_ref projection enum_table channel_id affordance kind name type
    profile_sha256 closure_sha256 capture_digest external_unit quantity_kind dimension scale_n scale_d offset_n offset_d
    observation receipt_clock source_ref source_epoch source_class source_time_basis source_origin_us target_epoch target_origin_ms
    sequence continuity replay receipt_time epoch monotonic_us source_time utc trust uncertainty_us normalized_value
    received_at receipt_epoch receipt_ms source_id source_time_trust source_uncertainty_ms expires_ms profile_digest
    contributors derivation_digest fact_id quality unit value thing_id affordance_type affordance_name
    limits reader_limits registry requires semantic_digest format byte_digest implementation_digest compiler_digest
    output security_contract lifecycle_contract required_contracts evidence sources freshness_ms require_source_time
    completion report_contract effects resource_roles repeat stop supersession partial_possible unknown_possible
    timing deadline_ms duration_ms dwell_ms cooldown_ms uncertainty analysis classification profile properties annotations
    title description tags min max enum source target)

  @doc false
  @spec admit(term(), term(), module() | nil) :: {:ok, term(), Limits.t()} | {:error, Error.t()}
  def admit(input, limits, module) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, data} <- Validation.unpack(input, module),
         :ok <- Wotex.JSON.validate(data, Validation.json_options(limits.data)),
         :ok <- Validation.bounded(data, limits) do
      {:ok, data, limits}
    else
      error -> refusal(error)
    end
  end

  @doc false
  @spec reader(atom(), atom(), list()) :: term()
  def reader(module, function, arguments) do
    apply(module, function, arguments)
  rescue
    error in UndefinedFunctionError ->
      if error.module == module and error.function == function and error.arity == length(arguments),
        do: Error.refusal(:missing_producer),
        else: Error.refusal(:invalid_input)
  end

  @doc false
  @spec text(term(), pos_integer(), String.t()) :: :ok | {:error, Error.t()}
  def text(value, maximum, path) do
    if is_binary(value) and byte_size(value) in 1..maximum and String.valid?(value) and
         not String.contains?(value, <<0>>), do: :ok, else: Error.refusal(:invalid_input, path)
  end

  @doc false
  @spec key(term(), String.t()) :: :ok | {:error, Error.t()}
  def key(value, path) do
    with :ok <- text(value, 128, path),
         true <- Regex.match?(~r/\A[a-zA-Z0-9._-]+\z/, value),
         do: :ok,
         else: (_ -> Error.refusal(:invalid_input, path))
  end

  @doc false
  @spec external_ref(term(), String.t()) :: :ok | {:error, Error.t()}
  def external_ref(data, path) do
    with :ok <- Validation.fields(data, ~w(id version sha256), [], path),
         :ok <- text(data["id"], 256, path),
         :ok <- Validation.iri(data["id"], path),
         :ok <- version(data["version"], path),
         do: digest(data["sha256"], 64, path)
  end

  defp version(value, path) do
    if is_binary(value) and byte_size(value) <= 17 and
         Regex.match?(~r/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/, value) and
         Enum.all?(String.split(value, "."), &(String.to_integer(&1) <= 65_535)),
       do: :ok,
       else: Error.refusal(:invalid_input, path)
  end

  @doc false
  @spec digest(term(), 32 | 64, String.t()) :: :ok | {:error, Error.t()}
  def digest(value, size, path) do
    if is_binary(value) and byte_size(value) == size and Regex.match?(~r/\A[0-9a-f]+\z/, value),
      do: :ok,
      else: Error.refusal(:invalid_input, path)
  end

  @doc false
  @spec signed(term(), String.t()) :: {:ok, integer()} | {:error, Error.t()}
  def signed(value, path) do
    if is_binary(value) and byte_size(value) <= 20 and
         Regex.match?(~r/\A(?:0|-?[1-9][0-9]*)\z/, value) do
      integer = String.to_integer(value)

      if integer in -9_223_372_036_854_775_808..9_223_372_036_854_775_807,
        do: {:ok, integer},
        else: Error.refusal(:invalid_input, path)
    else
      Error.refusal(:invalid_input, path)
    end
  end

  @doc false
  @spec hash(String.t(), term(), Limits.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def hash(prefix, data, limits) do
    case Wotex.JSON.encode(data, Validation.json_options(limits.data)) do
      {:ok, bytes} ->
        {:ok, Base.encode16(:crypto.hash(:sha256, prefix <> "\n" <> bytes), case: :lower)}

      error ->
        refusal(error)
    end
  end

  @doc false
  @spec legacy_ref(map()) :: map()
  def legacy_ref(data),
    do: %{
      "id" => data["id"],
      "version" => data["version"],
      "semantic_digest" => "sha256:" <> data["sha256"]
    }

  @doc false
  @spec refusal(term()) :: {:error, Error.t()}
  def refusal({:error, %{code: code, path: path}}) do
    mapped =
      case code do
        value
        when value in [
               :input_limit,
               :numeric_limit,
               :integer_overflow,
               :limit_or_json_error,
               :byte_limit_exceeded,
               :depth_limit_exceeded,
               :node_limit_exceeded,
               :string_limit_exceeded,
               :collection_limit_exceeded
             ] ->
          :input_limit

        value
        when value in [
               :unsupported_mapping,
               :unsupported_representation,
               :missing_producer,
               :stale_basis,
               :inexact_conversion,
               :incompatible_dimension
             ] ->
          value

        :unknown_required_contract ->
          :unsupported_mapping

        :out_of_domain ->
          :unsupported_representation

        :unsupported_semantics ->
          :unsupported_representation

        _ ->
          :invalid_input
      end

    Error.refusal(mapped, safe_path(path))
  end

  def refusal(_), do: Error.refusal(:invalid_input)

  defp safe_path(path) when is_binary(path) and byte_size(path) <= 512 do
    segments = String.split(path, "/", trim: true)
    known = Enum.take_while(segments, &(&1 in @path_fields or Regex.match?(~r/\A[0-9]{1,4}\z/, &1)))
    if known == [], do: "", else: "/" <> Enum.join(known, "/")
  end

  defp safe_path(_), do: ""
end
