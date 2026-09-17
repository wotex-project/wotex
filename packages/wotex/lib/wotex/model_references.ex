defmodule Wotex.ModelReferences do
  @moduledoc """
  Checks local references within a structurally admitted Thing Model.

  `tm:optional` entries must identify existing Property, Action or Event
  Affordances. Local `tm:ref` fragments must resolve in the supplied document;
  remote references must have an absolute URI and a fragment. Remote targets
  are never fetched or verified. Reference failures return `Wotex.Error` values
  with the location of the declaration that failed.

  The Thing Model validator composes this pass with schema and context checks.
  Calling it alone does not validate a Thing Model, expand referenced models or
  establish that a remote fragment contains a compatible definition. Recursive
  map traversal sorts keys, while arrays keep their declared order.

  ## Examples

      iex> Wotex.ModelReferences.errors(%{"properties" => %{"temperature" => %{}}, "tm:optional" => ["/properties/temperature"]})
      []
  """

  alias Wotex.{Error, JSON}

  @affordance_categories ~w(properties actions events)

  @doc "Returns semantic errors for unresolved local Thing Model references."
  @spec errors(map()) :: [Error.t()]
  def errors(document) when is_map(document) do
    optional_errors(document) ++ ref_errors(document, document, "/")
  end

  defp optional_errors(%{"tm:optional" => pointers} = document) when is_list(pointers) do
    pointers
    |> Enum.with_index()
    |> Enum.flat_map(fn {pointer, index} ->
      path = "/tm:optional/#{index}"

      if affordance_pointer?(pointer) and resolves?(document, pointer) do
        []
      else
        [unresolved(path, pointer, "tm:optional must point at an affordance in this model")]
      end
    end)
  end

  defp optional_errors(_), do: []

  defp ref_errors(%{"tm:ref" => reference} = value, document, path) do
    own =
      cond do
        not is_binary(reference) ->
          [unresolved(path <> "/tm:ref", reference, "tm:ref must be a string reference")]

        String.starts_with?(reference, "#") ->
          check_local(reference, document, path)

        true ->
          check_remote(reference, path)
      end

    own ++ ref_errors(Map.delete(value, "tm:ref"), document, path)
  end

  defp ref_errors(value, document, path) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.flat_map(fn {key, child} ->
      ref_errors(child, document, join(path, JSON.pointer_segment(key)))
    end)
  end

  defp ref_errors(values, document, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {child, index} -> ref_errors(child, document, join(path, index)) end)
  end

  defp ref_errors(_, _, _), do: []

  defp check_local("#" <> pointer, document, path) do
    if resolves?(document, pointer) do
      []
    else
      [unresolved(path <> "/tm:ref", "#" <> pointer, "local tm:ref must resolve in this model")]
    end
  end

  defp check_remote(reference, path) do
    uri = URI.parse(reference)

    if is_binary(uri.scheme) and uri.scheme != "" and is_binary(uri.fragment) do
      []
    else
      [
        unresolved(
          path <> "/tm:ref",
          reference,
          "remote tm:ref must be an absolute URI with a JSON Pointer fragment"
        )
      ]
    end
  end

  defp affordance_pointer?(pointer) when is_binary(pointer) do
    case String.split(pointer, "/") do
      ["", category, name] when category in @affordance_categories and name != "" -> true
      _ -> false
    end
  end

  defp affordance_pointer?(_), do: false

  defp resolves?(document, pointer) do
    match?({:ok, _value}, JSON.resolve_pointer(document, pointer))
  end

  defp unresolved(path, reference, message) do
    Error.new(:unresolved_model_reference, :semantic, message, path, %{
      reference: inspect(reference, limit: 10, printable_limit: 200)
    })
  end

  defp join("/", segment), do: "/" <> to_string(segment)
  defp join(path, segment), do: path <> "/" <> to_string(segment)
end
