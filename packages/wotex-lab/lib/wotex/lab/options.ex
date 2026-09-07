defmodule Wotex.Lab.Options do
  @moduledoc false

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

  def identifier?(_value), do: false
end
