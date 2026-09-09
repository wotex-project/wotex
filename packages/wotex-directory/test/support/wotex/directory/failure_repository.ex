defmodule Wotex.Directory.FailureRepository do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  @impl true
  def fetch(_, _, _), do: {:error, :unavailable}

  @impl true
  def insert(_, _, _), do: {:error, :unavailable}

  @impl true
  def replace(_, _, _, _), do: {:error, :unavailable}

  @impl true
  def delete(_, _, _, _), do: {:error, :unavailable}

  @impl true
  def list(_, _, _, _, _), do: {:error, :unavailable}

  @impl true
  def expire_due(_, _, _, _, _), do: {:error, :unavailable}
end
