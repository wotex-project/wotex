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

  @callback fetch(state(), String.t(), context()) ::
              {:ok, Entry.t()} | :not_found | {:error, term()}

  @callback insert(state(), Entry.t(), context()) ::
              {:ok, Entry.t()} | {:error, :already_exists | term()}

  @callback replace(state(), Entry.t(), pos_integer(), context()) ::
              {:ok, Entry.t()} | {:error, :conflict | :not_found | term()}

  @callback delete(state(), String.t(), pos_integer(), context()) ::
              :ok | {:error, :conflict | :not_found | term()}

  @callback list(state(), Query.t(), DateTime.t(), context()) ::
              {:ok, Page.t()} | {:error, :collection_changed | term()}

  @callback expire_due(state(), DateTime.t(), pos_integer(), strategy(), context()) ::
              {:ok, [Entry.t()]} | {:error, term()}
end
