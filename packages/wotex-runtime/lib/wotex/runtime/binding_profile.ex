defmodule Wotex.Runtime.BindingProfile do
  @moduledoc """
  Immutable declaration of operations and URI schemes a binding can execute.

  A profile is the consumer-neutral capability description used during Form
  selection. It names the URI schemes, exact TD 1.1 operations, and media types
  that one installed binding can handle. It contains no connection, credential,
  or provider configuration.

  List position, not `id`, determines precedence during selection. Scheme and
  media-type matching is case-insensitive; media-type parameters are ignored.

  ## Examples

      iex> alias Wotex.Runtime.BindingProfile
      iex> {:ok, profile} = BindingProfile.new(
      ...>   id: :https,
      ...>   schemes: ["https"],
      ...>   operations: [:readproperty],
      ...>   media_types: ["application/json"]
      ...> )
      iex> BindingProfile.supports_scheme?(profile, "HTTPS")
      true
      iex> BindingProfile.supports_media_type?(profile, "application/json; charset=utf-8")
      true
  """

  alias Wotex.Runtime.Error

  @operations Wotex.Runtime.operations()

  @type t :: %__MODULE__{
          id: atom() | String.t(),
          schemes: MapSet.t(String.t()),
          operations: MapSet.t(atom()),
          media_types: MapSet.t(String.t())
        }

  @enforce_keys [:id, :schemes, :operations, :media_types]
  defstruct [:id, :schemes, :operations, :media_types]

  @doc "Builds a binding profile from an id, URI schemes, operations, and media types."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      build(opts)
    else
      invalid_options()
    end
  end

  def new(_), do: invalid_options()

  defp build(opts) do
    id = Keyword.get(opts, :id)
    schemes = Keyword.get(opts, :schemes, [])
    operations = Keyword.get(opts, :operations, [])
    media_types = Keyword.get(opts, :media_types, [])

    with :ok <- validate_id(id),
         {:ok, normalized_schemes} <- normalize_schemes(schemes),
         {:ok, normalized_operations} <- normalize_operations(operations),
         {:ok, normalized_media_types} <- normalize_media_types(media_types) do
      {:ok,
       %__MODULE__{
         id: id,
         schemes: normalized_schemes,
         operations: normalized_operations,
         media_types: normalized_media_types
       }}
    end
  end

  defp invalid_options do
    {:error,
     Error.new(
       :invalid_profile_options,
       :construction,
       "binding profile options must be a keyword list"
     )}
  end

  @doc "Returns the stable consumer-selected profile id."
  @spec id(t()) :: atom() | String.t()
  def id(%__MODULE__{id: id}), do: id

  @doc "Returns whether the profile declares an operation."
  @spec supports_operation?(t(), atom()) :: boolean()
  def supports_operation?(%__MODULE__{operations: operations}, operation),
    do: MapSet.member?(operations, operation)

  @doc "Returns whether the profile declares a resolved URI scheme."
  @spec supports_scheme?(t(), String.t()) :: boolean()
  def supports_scheme?(%__MODULE__{schemes: schemes}, scheme) when is_binary(scheme),
    do: MapSet.member?(schemes, String.downcase(scheme))

  @doc "Returns whether the profile accepts a Form content type."
  @spec supports_media_type?(t(), String.t() | nil) :: boolean()
  def supports_media_type?(%__MODULE__{}, nil), do: true

  def supports_media_type?(%__MODULE__{media_types: media_types}, type) when is_binary(type) do
    if MapSet.size(media_types) == 0 do
      true
    else
      normalized = normalize_media_type(type)
      MapSet.member?(media_types, normalized) or MapSet.member?(media_types, "*/*")
    end
  end

  defp validate_id(id) when is_atom(id) and not is_nil(id), do: :ok
  defp validate_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok

  defp validate_id(_) do
    {:error,
     Error.new(:invalid_profile_id, :construction, "profile id must be an atom or non-empty string")}
  end

  defp normalize_schemes(values) when is_list(values) and values != [] do
    if Enum.all?(values, &(is_binary(&1) and byte_size(String.trim(&1)) > 0)) do
      normalized = Enum.map(values, &String.downcase/1)
      {:ok, MapSet.new(normalized)}
    else
      {:error,
       Error.new(
         :invalid_profile_schemes,
         :construction,
         "profile schemes must be non-empty strings"
       )}
    end
  end

  defp normalize_schemes(_) do
    {:error,
     Error.new(
       :invalid_profile_schemes,
       :construction,
       "profile must declare at least one URI scheme"
     )}
  end

  defp normalize_operations(values) when is_list(values) and values != [] do
    normalized = Enum.map(values, &normalize_operation/1)

    if Enum.all?(normalized, &(&1 in @operations)) do
      {:ok, MapSet.new(normalized)}
    else
      {:error,
       Error.new(
         :invalid_profile_operations,
         :construction,
         "profile contains an unsupported WoT operation"
       )}
    end
  end

  defp normalize_operations(_) do
    {:error,
     Error.new(
       :invalid_profile_operations,
       :construction,
       "profile must declare at least one WoT operation"
     )}
  end

  defp normalize_operation(value) when value in @operations, do: value

  defp normalize_operation(value) when is_binary(value) do
    Enum.find(@operations, :invalid, &(Atom.to_string(&1) == value))
  end

  defp normalize_operation(_), do: :invalid

  defp normalize_media_types(values) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and byte_size(String.trim(&1)) > 0)) do
      normalized = Enum.map(values, &normalize_media_type/1)
      {:ok, MapSet.new(normalized)}
    else
      {:error,
       Error.new(
         :invalid_profile_media_types,
         :construction,
         "media types must be non-empty strings"
       )}
    end
  end

  defp normalize_media_types(_) do
    {:error, Error.new(:invalid_profile_media_types, :construction, "media types must be a list")}
  end

  defp normalize_media_type(value) do
    value
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end
end
