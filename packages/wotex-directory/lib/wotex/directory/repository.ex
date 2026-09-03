defmodule Wotex.Directory.Repository do
  @moduledoc """
  Persistence-neutral repository port for one directory instance.

  Consumers implement atomic insert, conditional mutation, stable listing, and
  bounded expiry against their selected persistence system.
  """

  alias Wotex.Directory.{Entry, Page, Query}

  @type state :: term()
  @type context :: term()
  @type strategy :: :purge | :retain

  @doc "Fetches one entry by identifier."
  @callback fetch(state(), String.t(), context()) ::
              {:ok, Entry.t()} | :not_found | {:error, term()}

  @doc "Atomically inserts a new entry."
  @callback insert(state(), Entry.t(), context()) ::
              {:ok, Entry.t()} | {:error, :already_exists | term()}

  @doc "Atomically replaces an entry only when its expected revision matches."
  @callback replace(state(), Entry.t(), pos_integer(), context()) ::
              {:ok, Entry.t()} | {:error, :conflict | :not_found | term()}

  @doc "Atomically deletes an entry only when its expected revision matches."
  @callback delete(state(), String.t(), pos_integer(), context()) ::
              :ok | {:error, :conflict | :not_found | term()}

  @doc "Lists a stable, bounded page matching the validated query."
  @callback list(state(), Query.t(), DateTime.t(), context()) ::
              {:ok, Page.t()} | {:error, :collection_changed | term()}

  @doc "Expires at most `limit` due entries using the requested retention strategy."
  @callback expire_due(state(), DateTime.t(), pos_integer(), strategy(), context()) ::
              {:ok, [Entry.t()]} | {:error, term()}
end
