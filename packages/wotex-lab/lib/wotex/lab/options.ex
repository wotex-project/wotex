defmodule Wotex.Lab.Options do
  @moduledoc """
  Validates small trusted configuration boundaries shared by Lab components.

  Keyword admission requires a proper keyword list, unique keys and membership
  in the caller's allowlist. It returns a structured construction error for an
  invalid option list, duplicates or unknown keys. Each component separately
  validates option values and relationships; this helper does not make arbitrary
  nested configuration safe or choose modules from external input.

  Identifiers use 1..128 ASCII bytes, beginning with a lowercase letter or
  digit and continuing with lowercase letters, digits, dot, underscore, colon
  or hyphen.
  It does not allocate identifiers, enforce uniqueness, create atoms or consult
  a registry. Scenario values and supervision configuration use this predicate
  before applying their own ownership and resource limits.

  ## Examples

      iex> Wotex.Lab.Options.identifier?("lab:room-1")
      true
      iex> Wotex.Lab.Options.identifier?("Room")
      false
  """

  alias Wotex.Lab.Error

  @spec validate(term(), [atom()]) :: :ok | {:error, Error.t()}
  def validate(opts, allowed) do
    if Keyword.keyword?(opts) and
         length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
         Enum.all?(Keyword.keys(opts), &(&1 in allowed)) do
      :ok
    else
      {:error, Error.new(:invalid_options, :construction, "options must be unique known keywords")}
    end
  end

  @spec identifier?(term()) :: boolean()
  def identifier?(value) when is_binary(value) and byte_size(value) in 1..128,
    do: Regex.match?(~r/\A[a-z0-9][a-z0-9._:-]*\z/, value)

  def identifier?(_), do: false
end
