defmodule WotexContinuum.Error do
  @moduledoc """
  Typed validation or codec error.

  Paths use wire member names and zero-based list indexes.
  """

  @enforce_keys [:code, :message]
  defexception [:code, :message, path: [], details: %{}]

  @typedoc "A wire path segment."
  @type segment :: String.t() | non_neg_integer()

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          path: [segment()],
          details: map()
        }

  @doc false
  @spec error(atom(), [segment()], String.t(), map()) :: {:error, t()}
  def error(code, path, message, details \\ %{}) do
    {:error, %__MODULE__{code: code, path: path, message: message, details: details}}
  end

  @doc false
  @spec prepend(t(), segment()) :: t()
  def prepend(%__MODULE__{} = error, segment), do: %{error | path: [segment | error.path]}

  @impl Exception
  def message(%__MODULE__{message: message, path: []}), do: message

  def message(%__MODULE__{message: message, path: path}) do
    "#{render_path(path)}: #{message}"
  end

  defp render_path(path) do
    Enum.reduce(path, "$", fn
      segment, acc when is_integer(segment) -> "#{acc}[#{segment}]"
      segment, acc -> "#{acc}.#{segment}"
    end)
  end
end
