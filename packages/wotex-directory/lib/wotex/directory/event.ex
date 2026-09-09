defmodule Wotex.Directory.Event do
  @moduledoc """
  Transport-neutral W3C WoT Discovery directory lifecycle event.

  The Discovery Events API defines `thing_created`, `thing_updated`, and
  `thing_deleted` event types. This value derives their JSON-compatible event
  data from a successful `Wotex.Directory.Mutation` without starting a stream,
  assigning a replay identifier, or selecting a transport.

  A consumer that implements the optional Server-Sent Events API owns durable
  ordering, event identifiers, replay, filtering, authorization, and SSE
  encoding. The mutation and its derived event can be committed to a consumer
  outbox in the same repository transaction.
  """

  alias Wotex.Directory.{Entry, Error, Mutation}

  @enforce_keys [:type, :data]
  defstruct [:type, :data]

  @type type :: :thing_created | :thing_updated | :thing_deleted
  @type payload :: :full | :identifier
  @type t :: %__MODULE__{type: type(), data: map()}

  @spec from_mutation(Mutation.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  @doc """
  Derives lifecycle event data from a successful directory mutation.

  `payload: :full` includes the enriched Thing Description for create and
  update events. `payload: :identifier` emits the minimum Partial TD containing
  only `id`. Delete events always use that minimum representation because the
  described Thing Description is no longer registered.
  """
  def from_mutation(mutation, options \\ [])

  def from_mutation(%Mutation{entry: %Entry{} = entry} = mutation, options)
      when is_list(options) do
    with :ok <- validate_options(options),
         true <- Entry.valid?(entry),
         {:ok, type} <- event_type(mutation),
         {:ok, data} <- event_data(type, entry, Keyword.get(options, :payload, :full)) do
      {:ok, %__MODULE__{type: type, data: data}}
    else
      _ -> invalid(entry.identifier)
    end
  end

  def from_mutation(_, _), do: invalid(nil)

  defp event_type(%Mutation{operation: :register, status: :created}),
    do: {:ok, :thing_created}

  defp event_type(%Mutation{operation: :register, status: :replaced}),
    do: {:ok, :thing_updated}

  defp event_type(%Mutation{operation: :replace, status: :replaced}),
    do: {:ok, :thing_updated}

  defp event_type(%Mutation{operation: :patch, status: :patched}),
    do: {:ok, :thing_updated}

  defp event_type(%Mutation{operation: :delete, status: :deleted}),
    do: {:ok, :thing_deleted}

  defp event_type(_), do: :error

  defp event_data(:thing_deleted, entry, _), do: {:ok, identifier_data(entry)}
  defp event_data(_, entry, :identifier), do: {:ok, identifier_data(entry)}

  defp event_data(_, entry, :full) do
    with {:ok, thing_description} <- Entry.enriched_thing_description(entry) do
      {:ok, Wotex.ThingDescription.to_map(thing_description)}
    end
  end

  defp event_data(_, _, _), do: :error

  defp identifier_data(entry), do: %{"id" => entry.identifier}

  defp validate_options(options) do
    if Keyword.keyword?(options) and
         Enum.all?(Keyword.keys(options), &(&1 == :payload)) and
         Keyword.get(options, :payload, :full) in [:full, :identifier] do
      :ok
    else
      :error
    end
  end

  defp invalid(identifier) do
    {:error, Error.new(:invalid_request, :validation, :event, identifier: identifier)}
  end
end
