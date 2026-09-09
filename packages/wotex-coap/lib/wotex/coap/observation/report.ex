defmodule Wotex.CoAP.Observation.Report do
  @moduledoc """
  Validates an Observe report and retains its original representation identity.

  The first wire message and caller-supplied arrival time remain immutable while
  complete-body assembly supplies its result. Sequence, status and option metadata
  are decoded only from validated bytes. This value owns no timer, process or I/O.
  """

  alias Wotex.CoAP.{Codec, Error, Message}
  @enforce_keys [:first, :metadata, :received_at]
  defstruct [:first, :metadata, :received_at, :message]

  @type metadata :: %{
          code: 64..94,
          observe: 0..16_777_215,
          etag: binary() | nil,
          content_format: 0..65_535 | nil,
          max_age: 0..4_294_967_295
        }
  @opaque t :: %__MODULE__{
            first: Message.t(),
            metadata: metadata(),
            received_at: integer(),
            message: Message.t() | nil
          }

  @doc "Validates one bounded wire report at an explicit monotonic arrival time."
  @spec new(term(), integer()) :: {:ok, t()} | {:error, Error.t()}
  def new(first, now) when is_integer(now) do
    with :ok <- Codec.validate_options(first),
         {:ok, _} <- Codec.encode(first),
         :ok <- status(first),
         [sequence] <- Codec.option(first, 6),
         true <- length(Codec.option(first, 4)) <= 1 do
      metadata = %{
        code: first.code,
        observe: :binary.decode_unsigned(sequence),
        etag: first_value(first, 4, nil),
        content_format: integer_option(first, 12, nil),
        max_age: integer_option(first, 14, 60)
      }

      {:ok, %__MODULE__{first: first, metadata: metadata, received_at: now}}
    else
      {:error, _} = error -> error
      _ -> invalid()
    end
  end

  def new(_, _), do: invalid()

  @doc "Admits a complete body only when every retained first-report field matches."
  @spec complete(t(), Message.t()) :: {:ok, t()} | {:error, Error.t()}
  def complete(report, message) do
    with :ok <- validate(report),
         :ok <- Codec.validate_options(message),
         true <- byte_size(message.payload) <= 1_048_576,
         expected = %{
           report.first
           | payload: message.payload,
             options: Enum.reject(report.first.options, &(elem(&1, 0) in [23, 27]))
         },
         true <- message == expected do
      {:ok, %{report | message: message}}
    else
      {:error, _} = error -> error
      _ -> invalid()
    end
  end

  @doc "Checks a retained report, including any completed body's exact identity."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(
        %__MODULE__{first: first, metadata: metadata, received_at: now, message: complete} = report
      )
      when map_size(report) == 5 do
    with {:ok, reconstructed} <- new(first, now),
         true <- metadata == reconstructed.metadata do
      validate_complete(first, complete)
    else
      _ -> invalid()
    end
  end

  def validate(_), do: invalid()

  defp validate_complete(_, nil), do: :ok

  defp validate_complete(first, complete) do
    with :ok <- Codec.validate_options(complete),
         true <- byte_size(complete.payload) <= 1_048_576,
         true <-
           complete == %{
             first
             | payload: complete.payload,
               options: Enum.reject(first.options, &(elem(&1, 0) in [23, 27]))
           },
         do: :ok,
         else: (_ -> invalid())
  end

  defp status(%Message{code: code}) when code in 64..94, do: :ok

  defp status(%Message{code: code}) when code in 128..191,
    do: {:error, Error.new(:remote_response, nil, %{code: code})}

  defp status(_), do: invalid()

  defp first_value(message, option, default) do
    case Codec.option(message, option) do
      [] -> default
      [value] -> value
    end
  end

  defp integer_option(message, option, default) do
    case first_value(message, option, nil) do
      nil -> default
      value -> :binary.decode_unsigned(value)
    end
  end

  defp invalid, do: {:error, Error.new(:invalid_observation_response)}
end
