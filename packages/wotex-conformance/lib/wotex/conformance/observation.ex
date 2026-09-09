defmodule Wotex.Conformance.Observation do
  @moduledoc """
  Normalized input and observation contract for document operations.

  Vectors whose claim operation is `thing_description.parse`,
  `thing_description.validate`, `thing_model.parse`, or `thing_model.validate`
  declare an input document and a projection, and expect exactly one
  normalized observation shape:

      %{"accepted" => true, "document" => projected_members}
      %{"accepted" => false, "errors" => [%{"code" => c, "phase" => p, "path" => pointer}]}

  A projection is a list of RFC 6901 JSON Pointers. The accepted observation
  maps each declared pointer that resolves in the accepted document to its
  member value; a declared pointer that does not resolve is omitted, so
  absence is observable evidence. An empty projection declares the whole
  canonical accepted document.

  A rejected observation lists bounded `code`, `phase`, and `path`
  identifiers, sorted ascending by `path` and then `code`. Messages, details,
  and raw values are not observation members, because only codes, phases, and
  paths are stable across subject revisions.

  Other operations carry no normalized shape at this revision and are accepted
  as bounded JSON values.
  """

  alias Wotex.Conformance.{Error, Pointer, Value}

  @operations ~w(
    thing_description.parse
    thing_description.validate
    thing_model.parse
    thing_model.validate
  )

  @max_projection 64
  @max_pointer_bytes 256
  @max_errors 64
  @max_identifier_bytes 128
  @identifier ~r/^[a-z][a-z0-9_]*$/

  @doc "Returns the operations that use the normalized document contract."
  @spec operations() :: [String.t()]
  def operations, do: @operations

  @doc "Reports whether an operation uses the normalized document contract."
  @spec document_operation?(term()) :: boolean()
  def document_operation?(operation), do: operation in @operations

  @doc """
  Validates the declared vector input of a document operation.

  The input is an object with a `document` object and a `projection` list of
  bounded, unique JSON Pointers. Other operations pass through unchanged.
  """
  @spec validate_input(term(), Value.json_value()) ::
          {:ok, Value.json_value()} | {:error, Error.t()}
  def validate_input(operation, input) do
    if document_operation?(operation) do
      with :ok <-
             object(input, ~w(document projection), ["input"], :invalid_vector_input, :vector),
           :ok <- document(Map.get(input, "document"), ["input", "document"], :vector),
           :ok <- projection(Map.get(input, "projection")) do
        {:ok, input}
      end
    else
      {:ok, input}
    end
  end

  @doc """
  Validates one normalized observation of a document operation.

  Other operations pass through unchanged.
  """
  @spec validate(term(), Value.json_value()) :: {:ok, Value.json_value()} | {:error, Error.t()}
  def validate(operation, value) do
    if document_operation?(operation) do
      accepted(value)
    else
      {:ok, value}
    end
  end

  defp accepted(%{"accepted" => true} = value) do
    with :ok <-
           object(value, ~w(accepted document), ["observation"], :invalid_observation, :protocol),
         :ok <- document(Map.get(value, "document"), ["observation", "document"], :protocol) do
      {:ok, value}
    end
  end

  defp accepted(%{"accepted" => false} = value) do
    with :ok <-
           object(value, ~w(accepted errors), ["observation"], :invalid_observation, :protocol),
         :ok <- observation_errors(Map.get(value, "errors")) do
      {:ok, value}
    end
  end

  defp accepted(_) do
    {:error,
     Error.new(:invalid_observation, :protocol, "observation requires a boolean accepted member",
       path: ["observation", "accepted"]
     )}
  end

  defp object(value, keys, path, code, phase) when is_map(value) do
    if Enum.sort(Map.keys(value)) == Enum.sort(keys) do
      :ok
    else
      {:error,
       Error.new(code, phase, "value members are not the declared normalized members",
         path: path,
         details: %{"members" => Enum.sort(keys)}
       )}
    end
  end

  defp object(_, _, path, code, phase) do
    {:error, Error.new(code, phase, "value must be an object", path: path)}
  end

  defp document(document, _, _) when is_map(document) and not is_struct(document), do: :ok

  defp document(_, path, phase) do
    {:error, Error.new(:invalid_document, phase, "document must be an object", path: path)}
  end

  defp projection(pointers) when is_list(pointers) and length(pointers) <= @max_projection do
    cond do
      not Enum.all?(pointers, &valid_pointer?/1) ->
        {:error,
         Error.new(:invalid_projection, :vector, "projection members must be bounded pointers",
           path: ["input", "projection"],
           details: %{"max_pointer_bytes" => @max_pointer_bytes}
         )}

      length(Enum.uniq(pointers)) != length(pointers) ->
        {:error,
         Error.new(:invalid_projection, :vector, "projection members must be unique",
           path: ["input", "projection"]
         )}

      true ->
        :ok
    end
  end

  defp projection(_) do
    {:error,
     Error.new(:invalid_projection, :vector, "projection must be a bounded list of pointers",
       path: ["input", "projection"],
       details: %{"max_projection" => @max_projection}
     )}
  end

  defp valid_pointer?(pointer) when is_binary(pointer) do
    pointer != "" and byte_size(pointer) <= @max_pointer_bytes and Pointer.valid?(pointer)
  end

  defp valid_pointer?(_), do: false

  defp observation_errors(errors)
       when is_list(errors) and errors != [] and length(errors) <= @max_errors do
    with :ok <- observation_error_members(errors) do
      sorted = Enum.sort_by(errors, &{&1["path"], &1["code"]})

      if sorted == errors and length(Enum.uniq(sorted)) == length(sorted) do
        :ok
      else
        {:error,
         Error.new(
           :unsorted_observation_errors,
           :protocol,
           "observation errors must be unique and sorted by path and code",
           path: ["observation", "errors"]
         )}
      end
    end
  end

  defp observation_errors(_) do
    {:error,
     Error.new(:invalid_observation, :protocol, "observation errors must be a bounded list",
       path: ["observation", "errors"],
       details: %{"max_errors" => @max_errors}
     )}
  end

  defp observation_error_members(errors) do
    Enum.reduce_while(errors, :ok, fn error, :ok ->
      case observation_error(error) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp observation_error(error) when is_map(error) do
    with :ok <-
           object(
             error,
             ~w(code phase path),
             ["observation", "errors"],
             :invalid_observation,
             :protocol
           ) do
      if bounded_identifier?(error["code"]) and bounded_identifier?(error["phase"]) and
           valid_pointer?(error["path"]) do
        :ok
      else
        {:error,
         Error.new(
           :invalid_observation,
           :protocol,
           "observation error members must be bounded identifiers and one pointer",
           path: ["observation", "errors"],
           details: %{"max_identifier_bytes" => @max_identifier_bytes}
         )}
      end
    end
  end

  defp observation_error(_) do
    {:error,
     Error.new(:invalid_observation, :protocol, "observation error must be an object",
       path: ["observation", "errors"]
     )}
  end

  defp bounded_identifier?(value) when is_binary(value) do
    byte_size(value) <= @max_identifier_bytes and Regex.match?(@identifier, value)
  end

  defp bounded_identifier?(_), do: false
end
