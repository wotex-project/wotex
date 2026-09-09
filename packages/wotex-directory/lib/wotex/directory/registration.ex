defmodule Wotex.Directory.Registration do
  @moduledoc """
  W3C WoT Discovery registration information for one directory entry.

  `created`, `modified`, and `retrieved` are assigned by the directory. A
  relative `ttl` takes precedence over a supplied absolute `expires` value.
  Unknown string-keyed members are preserved as extension terms.

  Creation and refresh operations derive absolute expiry from the current
  time when a time-to-live (`ttl`) is present. The accepted range is zero
  through 4,294,967,295 seconds. Refresh preserves `created`, sets
  `modified` to the supplied time, and rejects a clock value earlier than the stored modification
  time. Merge-patch reconstruction applies the same value invariants.

  `retrieved` belongs only to a response representation and is removed by
  `for_storage/1`. `to_map/1` emits JSON-compatible Discovery members, while
  `valid?/1` checks timestamp ordering, relative expiry, extension values, and
  the remaining struct invariant. This module represents registration data;
  repository persistence and expiry deletion belong to the directory service.
  """

  alias Wotex.Directory.{Error, MergePatch}

  @maximum_ttl 4_294_967_295
  @server_fields ~w(created modified retrieved)
  @standard_fields ~w(created modified expires ttl retrieved)

  @enforce_keys [:created, :modified]
  defstruct [:created, :modified, :expires, :ttl, :retrieved, extensions: %{}]

  @type t :: %__MODULE__{
          created: DateTime.t(),
          modified: DateTime.t(),
          expires: DateTime.t() | nil,
          ttl: non_neg_integer() | nil,
          retrieved: DateTime.t() | nil,
          extensions: %{optional(String.t()) => term()}
        }

  @type input :: :absent | {:present, map()}

  @spec create(DateTime.t(), input(), atom()) :: {:ok, t()} | {:error, Error.t()}
  @doc "Creates server-assigned registration information from registration input."
  def create(%DateTime{} = now, input, operation) do
    with {:ok, values} <- parse_input(input, operation, reject_server_fields?: true),
         {:ok, expires} <- expiry(now, values.ttl, values.expires, operation) do
      {:ok,
       %__MODULE__{
         created: now,
         modified: now,
         expires: expires,
         ttl: values.ttl,
         extensions: values.extensions
       }}
    end
  end

  def create(_now, _input, operation), do: invalid(operation)

  @spec refresh(t(), DateTime.t(), input(), atom()) :: {:ok, t()} | {:error, Error.t()}
  @doc "Refreshes registration information while preserving its creation time."
  def refresh(%__MODULE__{} = registration, %DateTime{} = now, input, operation) do
    with :ok <- ensure_clock(registration, now, operation),
         {:ok, values} <- refresh_values(registration, input, operation),
         {:ok, expires} <- expiry(now, values.ttl, values.expires, operation) do
      {:ok,
       %__MODULE__{
         created: registration.created,
         modified: now,
         expires: expires,
         ttl: values.ttl,
         extensions: values.extensions
       }}
    end
  end

  def refresh(_registration, _now, _input, operation), do: invalid(operation)

  @spec from_patch(t(), DateTime.t(), map(), atom()) :: {:ok, t()} | {:error, Error.t()}
  @doc "Rebuilds registration information after a validated merge patch."
  def from_patch(%__MODULE__{} = registration, %DateTime{} = now, raw, operation)
      when is_map(raw) do
    with :ok <- ensure_clock(registration, now, operation),
         {:ok, values} <- parse_input({:present, raw}, operation, reject_server_fields?: false),
         {:ok, expires} <- expiry(now, values.ttl, values.expires, operation) do
      {:ok,
       %__MODULE__{
         created: registration.created,
         modified: now,
         expires: expires,
         ttl: values.ttl,
         extensions: values.extensions
       }}
    end
  end

  def from_patch(_registration, _now, _raw, operation), do: invalid(operation)

  @spec mark_retrieved(t(), DateTime.t()) :: t()
  @doc "Assigns the response-only retrieval time."
  def mark_retrieved(%__MODULE__{} = registration, %DateTime{} = now) do
    %{registration | retrieved: now}
  end

  @spec for_storage(t()) :: t()
  @doc "Removes response-only retrieval information before persistence."
  def for_storage(%__MODULE__{} = registration), do: %{registration | retrieved: nil}

  @spec expired?(t(), DateTime.t()) :: boolean()
  @doc "Reports whether absolute expiry is at or before the supplied time."
  def expired?(%__MODULE__{expires: nil}, %DateTime{}), do: false

  def expired?(%__MODULE__{expires: %DateTime{} = expires}, %DateTime{} = now) do
    DateTime.compare(expires, now) in [:lt, :eq]
  end

  @spec valid?(term()) :: boolean()
  @doc "Reports whether registration information satisfies its value invariant."
  def valid?(%__MODULE__{} = registration) do
    valid_datetime?(registration.created) and valid_datetime?(registration.modified) and
      valid_optional_datetime?(registration.expires) and
      valid_optional_datetime?(registration.retrieved) and valid_ttl?(registration.ttl) and
      is_map(registration.extensions) and
      DateTime.compare(registration.modified, registration.created) != :lt and
      valid_retrieved?(registration) and valid_relative_expiry?(registration) and
      match?({:ok, _validated}, MergePatch.apply(%{}, registration.extensions))
  end

  def valid?(_registration), do: false

  @spec to_map(t()) :: map()
  @doc "Returns JSON-compatible Discovery registration information."
  def to_map(%__MODULE__{} = registration) do
    registration.extensions
    |> put_datetime("created", registration.created)
    |> put_datetime("modified", registration.modified)
    |> put_optional_datetime("expires", registration.expires)
    |> put_optional_integer("ttl", registration.ttl)
    |> put_optional_datetime("retrieved", registration.retrieved)
  end

  @spec server_field_patch?(term()) :: boolean()
  @doc false
  def server_field_patch?(patch) when is_map(patch) do
    case Map.fetch(patch, "registration") do
      :error ->
        false

      {:ok, registration} when is_map(registration) ->
        Enum.any?(@server_fields, &Map.has_key?(registration, &1))

      {:ok, _registration} ->
        true
    end
  end

  def server_field_patch?(_patch), do: false

  defp refresh_values(registration, :absent, _operation) do
    {:ok,
     %{
       ttl: registration.ttl,
       expires: registration.expires,
       extensions: registration.extensions
     }}
  end

  defp refresh_values(_registration, {:present, _raw} = input, operation) do
    parse_input(input, operation, reject_server_fields?: true)
  end

  defp refresh_values(_registration, _input, operation), do: invalid(operation)

  defp parse_input(:absent, _operation, _options) do
    {:ok, %{ttl: nil, expires: nil, extensions: %{}}}
  end

  defp parse_input({:present, raw}, operation, options) when is_map(raw) do
    reject_server_fields? = Keyword.fetch!(options, :reject_server_fields?)

    with :ok <- validate_keys(raw, operation),
         {:ok, _validated} <- validate_json(Map.drop(raw, @standard_fields), operation),
         :ok <- validate_server_fields(raw, reject_server_fields?, operation),
         {:ok, ttl} <- parse_ttl(Map.get(raw, "ttl"), operation),
         {:ok, expires} <- parse_datetime(Map.get(raw, "expires"), operation) do
      {:ok,
       %{
         ttl: ttl,
         expires: expires,
         extensions: Map.drop(raw, @standard_fields)
       }}
    end
  end

  defp parse_input(_input, operation, _options), do: invalid(operation)

  defp validate_keys(raw, operation) do
    if Enum.all?(Map.keys(raw), &is_binary/1), do: :ok, else: invalid(operation)
  end

  defp validate_json(raw, operation) do
    case MergePatch.apply(%{}, raw) do
      {:ok, validated} -> {:ok, validated}
      {:error, _reason} -> invalid(operation)
    end
  end

  defp validate_server_fields(_raw, false, _operation), do: :ok

  defp validate_server_fields(raw, true, operation) do
    case Enum.find(@server_fields, &Map.has_key?(raw, &1)) do
      nil -> :ok
      field -> invalid(operation, "/registration/" <> field)
    end
  end

  defp parse_ttl(nil, _operation), do: {:ok, nil}

  defp parse_ttl(ttl, _operation)
       when is_integer(ttl) and ttl >= 0 and ttl <= @maximum_ttl,
       do: {:ok, ttl}

  defp parse_ttl(_ttl, operation), do: invalid(operation, "/registration/ttl")

  defp parse_datetime(nil, _operation), do: {:ok, nil}
  defp parse_datetime(%DateTime{} = value, _operation), do: {:ok, value}

  defp parse_datetime(value, operation) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> invalid(operation, "/registration/expires")
    end
  end

  defp parse_datetime(_value, operation), do: invalid(operation, "/registration/expires")

  defp expiry(now, ttl, _expires, operation) when is_integer(ttl) do
    now
    |> DateTime.to_unix(:second)
    |> Kernel.+(ttl)
    |> DateTime.from_unix(:second)
    |> case do
      {:ok, expires} -> {:ok, expires}
      {:error, _reason} -> invalid(operation)
    end
  end

  defp expiry(_now, nil, expires, _operation), do: {:ok, expires}

  defp ensure_clock(%__MODULE__{modified: modified}, now, operation) do
    if DateTime.compare(now, modified) == :lt do
      {:error, Error.new(:clock_regression, :clock, operation)}
    else
      :ok
    end
  end

  defp valid_datetime?(%DateTime{}), do: true
  defp valid_datetime?(_value), do: false

  defp valid_optional_datetime?(nil), do: true
  defp valid_optional_datetime?(value), do: valid_datetime?(value)

  defp valid_ttl?(nil), do: true
  defp valid_ttl?(value), do: is_integer(value) and value >= 0 and value <= @maximum_ttl

  defp valid_retrieved?(%__MODULE__{retrieved: nil}), do: true

  defp valid_retrieved?(%__MODULE__{} = registration) do
    DateTime.compare(registration.retrieved, registration.modified) != :lt
  end

  defp valid_relative_expiry?(%__MODULE__{ttl: nil}), do: true

  defp valid_relative_expiry?(%__MODULE__{} = registration) do
    case expiry(registration.modified, registration.ttl, nil, :service) do
      {:ok, expected} -> registration.expires == expected
      {:error, _error} -> false
    end
  end

  defp put_datetime(map, key, datetime), do: Map.put(map, key, DateTime.to_iso8601(datetime))

  defp put_optional_datetime(map, _key, nil), do: map

  defp put_optional_datetime(map, key, datetime),
    do: Map.put(map, key, DateTime.to_iso8601(datetime))

  defp put_optional_integer(map, _key, nil), do: map
  defp put_optional_integer(map, key, value), do: Map.put(map, key, value)

  defp invalid(operation, path \\ nil) do
    {:error, Error.new(:invalid_request, :validation, operation, path: path)}
  end
end
