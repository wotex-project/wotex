defmodule Wotex.Directory.Entry do
  @moduledoc """
  Storage-neutral directory entry for one validated Thing Description.

  `version` is an optimistic-concurrency value. `state` and `version` are
  package mechanics and are never emitted as W3C terms.

  An entry contains the validated core `Wotex.ThingDescription`, its
  `Wotex.Directory.Registration` information, and the identifier by which the
  repository addresses it. Construction requires the Thing Description `id`
  to equal the entry identifier and excludes the Discovery `registration`
  member from the stored core document.

  Retrieval can attach a response-only timestamp with `mark_retrieved/2`.
  Call `for_storage/1` before persistence to remove that value, or
  `enriched_thing_description/2` to produce the W3C Discovery representation.
  `active?/2` combines the explicit entry state with the registration expiry
  time; it does not mutate or delete expired data.
  """

  alias Wotex.Directory.{Error, Identifier, Registration, ThingDescriptions}

  @enforce_keys [:identifier, :thing_description, :registration, :version, :state]
  defstruct [:identifier, :thing_description, :registration, :version, :state]

  @type state :: :active | :expired
  @type t :: %__MODULE__{
          identifier: String.t(),
          thing_description: Wotex.ThingDescription.t(),
          registration: Registration.t(),
          version: pos_integer(),
          state: state()
        }

  @spec new(String.t(), Wotex.ThingDescription.t(), Registration.t(), keyword()) ::
          {:ok, t()} | {:error, Error.t()}
  @doc "Builds a validated storage-neutral directory entry."
  def new(identifier, thing_description, registration, options \\ [])

  def new(identifier, thing_description, %Registration{} = registration, options)
      when is_list(options) do
    if valid_options?(options) do
      version = Keyword.get(options, :version, 1)
      state = Keyword.get(options, :state, :active)

      if Identifier.valid?(identifier) and valid_thing_description?(thing_description, identifier) and
           Registration.valid?(registration) and is_integer(version) and version > 0 and
           state in [:active, :expired] do
        {:ok,
         %__MODULE__{
           identifier: identifier,
           thing_description: thing_description,
           registration: Registration.for_storage(registration),
           version: version,
           state: state
         }}
      else
        invalid(identifier)
      end
    else
      invalid(identifier)
    end
  end

  def new(identifier, _thing_description, _registration, _options) do
    invalid(identifier)
  end

  @spec valid?(term()) :: boolean()
  @doc "Reports whether an entry satisfies the complete value invariant."
  def valid?(%__MODULE__{} = entry) do
    case new(
           entry.identifier,
           entry.thing_description,
           entry.registration,
           version: entry.version,
           state: entry.state
         ) do
      {:ok, normalized} -> normalized == entry
      {:error, _error} -> false
    end
  end

  def valid?(_entry), do: false

  @spec active?(t(), DateTime.t()) :: boolean()
  @doc "Reports whether an entry is active at the supplied time."
  def active?(%__MODULE__{state: :expired}, %DateTime{}), do: false

  def active?(%__MODULE__{state: :active, registration: registration}, %DateTime{} = now) do
    not Registration.expired?(registration, now)
  end

  @spec mark_retrieved(t(), DateTime.t()) :: t()
  @doc "Returns an entry whose response-only retrieval time is assigned."
  def mark_retrieved(%__MODULE__{} = entry, %DateTime{} = now) do
    %{entry | registration: Registration.mark_retrieved(entry.registration, now)}
  end

  @spec for_storage(t()) :: t()
  @doc "Removes response-only retrieval information before persistence."
  def for_storage(%__MODULE__{} = entry) do
    %{entry | registration: Registration.for_storage(entry.registration)}
  end

  @spec enriched_thing_description(t(), keyword()) ::
          {:ok, Wotex.ThingDescription.t()} | {:error, Error.t()}
  @doc "Returns the Thing Description enriched with Discovery registration information."
  def enriched_thing_description(%__MODULE__{} = entry, options \\ []) do
    ThingDescriptions.enriched(
      entry.thing_description,
      entry.registration,
      options,
      :get
    )
  end

  defp safe_identifier(identifier) when is_binary(identifier), do: identifier
  defp safe_identifier(_identifier), do: nil

  defp invalid(identifier) do
    {:error,
     Error.new(:invalid_request, :validation, :service, identifier: safe_identifier(identifier))}
  end

  defp valid_options?(options) do
    Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in [:version, :state]))
  end

  defp valid_thing_description?(%Wotex.ThingDescription{} = thing_description, identifier) do
    case Wotex.ThingDescription.validate(thing_description) do
      {:ok, _validated} ->
        ThingDescriptions.id(thing_description) == identifier and
          not Map.has_key?(Wotex.ThingDescription.to_map(thing_description), "registration")

      {:error, _errors} ->
        false
    end
  end

  defp valid_thing_description?(_thing_description, _identifier), do: false
end
