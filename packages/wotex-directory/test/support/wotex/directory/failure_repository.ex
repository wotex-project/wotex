defmodule Wotex.Directory.FailureRepository do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  @impl Wotex.Directory.Repository
  def fetch(_, _, _), do: {:error, :unavailable}

  @impl Wotex.Directory.Repository
  def insert(_, _, _), do: {:error, :unavailable}

  @impl Wotex.Directory.Repository
  def replace(_, _, _, _), do: {:error, :unavailable}

  @impl Wotex.Directory.Repository
  def delete(_, _, _, _), do: {:error, :unavailable}

  @impl Wotex.Directory.Repository
  def list(_, _, _, _, _), do: {:error, :unavailable}

  @impl Wotex.Directory.Repository
  def expire_due(_, _, _, _, _), do: {:error, :unavailable}
end
