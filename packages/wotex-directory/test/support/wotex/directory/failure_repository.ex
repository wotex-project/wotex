defmodule Wotex.Directory.FailureRepository do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  @impl true
  def fetch(_state, _identifier, _context), do: {:error, :unavailable}

  @impl true
  def insert(_state, _entry, _context), do: {:error, :unavailable}

  @impl true
  def replace(_state, _entry, _expected_version, _context), do: {:error, :unavailable}

  @impl true
  def delete(_state, _identifier, _expected_version, _context), do: {:error, :unavailable}

  @impl true
  def list(_state, _query, _cursor, _active_at, _context), do: {:error, :unavailable}

  @impl true
  def expire_due(_state, _cutoff, _limit, _strategy, _context), do: {:error, :unavailable}
end
