defmodule Wotex.Directory.Repository do
  @moduledoc """
  Persistence-neutral repository port for one directory instance.

  Consumers implement conditional creation, conditional mutation, keyset
  listing, and bounded expiry against their selected persistence system. Each
  callback is one unit of work: the package never wraps two callbacks in one
  logical transaction, never retries a callback, and never compensates a
  partially applied callback.

  ## Atomicity and isolation

  - `fetch/3` reads one committed entry. A read that races a concurrent
    mutation may observe either committed value; the package revalidates the
    returned entry and applies its own version precondition afterwards.
  - `insert/3` is an atomic conditional create. It must fail with
    `{:error, :already_exists}` when the identifier is already present rather
    than overwrite it, so two concurrent creators cannot both succeed.
  - `replace/4` and `delete/4` compare `expected_version` and apply the change
    in one atomic step. They report `{:error, :conflict}` on a version mismatch
    and `{:error, :not_found}` when the entry is absent.
  - `list/5` observes one committed snapshot for the page it returns. It never
    mixes entries from two orderings inside one page.
  - `expire_due/5` selects and changes its bounded batch in one transaction.
  - Every successful mutation advances the collection revision exactly once,
    independently of the number of affected entries. An expiry batch that
    changed no entry leaves the revision unchanged.

  A consumer that requires a stronger guarantee, such as read-your-writes
  across two operations or an outbox committed with a mutation, owns that
  transaction boundary in its adapter.
  """

  alias Wotex.Directory.{Cursor, Entry, Page, Query}

  @type state :: term()
  @type context :: term()
  @type strategy :: :purge | :retain

  @doc """
  Fetches one entry by identifier from committed state.

  The callback interprets no consumer scope beyond the supplied context and
  reports absence as `:not_found` or `{:error, :not_found}`.
  """
  @callback fetch(state(), String.t(), context()) ::
              {:ok, Entry.t()} | :not_found | {:error, term()}

  @doc """
  Atomically creates a new entry.

  The callback must reject an existing identifier with
  `{:error, :already_exists}`. A named registration that loses this race is
  reported to the caller as `conflict`; the package never retries it.
  """
  @callback insert(state(), Entry.t(), context()) ::
              {:ok, Entry.t()} | {:error, :already_exists | term()}

  @doc """
  Atomically replaces an entry only when its expected version matches.

  The comparison and the write are one step; a mismatch is `{:error, :conflict}`
  and an absent entry is `{:error, :not_found}`.
  """
  @callback replace(state(), Entry.t(), pos_integer(), context()) ::
              {:ok, Entry.t()} | {:error, :conflict | :not_found | term()}

  @doc """
  Atomically deletes an entry only when its expected version matches.

  The comparison and the delete are one step; a mismatch is
  `{:error, :conflict}` and an absent entry is `{:error, :not_found}`.
  """
  @callback delete(state(), String.t(), pos_integer(), context()) ::
              :ok | {:error, :conflict | :not_found | term()}

  @doc """
  Lists one bounded keyset page of active entries.

  The callback excludes entries that are expired at `active_at`, orders by
  identifier in ascending Unicode code point order, and returns at most
  `query.limit` entries built with `Wotex.Directory.Page.new/1`.

  `cursor` is `nil` for the first page. Otherwise it is a decoded
  `Wotex.Directory.Cursor` and the callback selects only entries whose
  identifier is greater than `cursor.last_identifier`. When
  `cursor.collection_revision` is no longer the current collection revision the
  callback returns `{:error, :collection_changed}` and never silently pages
  into a different mutation generation. Membership that changed only because an
  entry reached absolute expiry does not change the collection revision.
  """
  @callback list(state(), Query.t(), Cursor.t() | nil, DateTime.t(), context()) ::
              {:ok, Page.t()} | {:error, :collection_changed | term()}

  @doc """
  Expires at most `limit` due entries in one bounded transaction.

  `retain` selects only due active entries, changes each to `expired`, and
  advances each selected version once. `purge` removes due active entries and
  due entries previously retained as expired. Returned entries are ordered by
  identifier in ascending Unicode code point order.
  """
  @callback expire_due(state(), DateTime.t(), pos_integer(), strategy(), context()) ::
              {:ok, [Entry.t()]} | {:error, term()}
end
