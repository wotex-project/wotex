defmodule Wotex.OPCUA.Native.HostOptions do
  @moduledoc """
  Validates explicit native bootstrap options before filesystem or process I/O.

  Four options are required: `:executable`, `:executable_digest`, `:guardian`,
  and `:guardian_digest`. Paths are absolute UTF-8 strings of at most 4096 bytes
  without NUL; digests are lowercase SHA-256 hexadecimal. `:timeout` defaults to
  5000 milliseconds and accepts 1..60000. Unknown, duplicate and malformed keyword
  entries fail instead of being discarded. This constructor does not read files
  or establish that an executable exists or matches its supplied digest.

  ## Examples

      iex> Wotex.OPCUA.Native.HostOptions.new([])
      {:error, %Wotex.OPCUA.Error{code: :invalid_native_configuration}}
  """

  alias Wotex.OPCUA.Error

  @required [:executable, :executable_digest, :guardian, :guardian_digest]
  @keys [:timeout | @required]
  @enforce_keys @required
  @derive {Inspect, only: [:timeout]}
  defstruct [{:timeout, 5000} | @required]

  @type t :: %__MODULE__{
          executable: String.t(),
          executable_digest: String.t(),
          guardian: String.t(),
          guardian_digest: String.t(),
          timeout: pos_integer()
        }

  @doc "Returns a pure bootstrap configuration only when all options and identities are well-formed."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) do
    with {:ok, values} <- fields(options, %{}),
         true <- Enum.all?(@required, &Map.has_key?(values, &1)),
         true <- path?(values.executable) and path?(values.guardian),
         true <- digest?(values.executable_digest) and digest?(values.guardian_digest),
         timeout when is_integer(timeout) and timeout in 1..60_000 <-
           Map.get(values, :timeout, 5000) do
      {:ok, struct!(__MODULE__, Map.put(values, :timeout, timeout))}
    else
      _ -> {:error, Error.new(:invalid_native_configuration)}
    end
  end

  defp fields([], values), do: {:ok, values}

  defp fields([{key, value} | rest], values) when key in @keys do
    if Map.has_key?(values, key), do: :error, else: fields(rest, Map.put(values, key, value))
  end

  defp fields(_, _), do: :error

  defp path?(path) when is_binary(path) do
    byte_size(path) in 1..4096 and String.valid?(path) and Path.type(path) == :absolute and
      not String.contains?(path, <<0>>)
  end

  defp path?(_), do: false

  defp digest?(digest) when is_binary(digest) and byte_size(digest) == 64,
    do: Regex.match?(~r/\A[0-9a-f]{64}\z/, digest)

  defp digest?(_), do: false
end
