defmodule Wotex.Check.WCFTarget do
  @moduledoc false

  alias Wotex.{Error, JSON, ThingDescription, ThingModel}

  @protocol "wotex.conformance.target"
  @protocol_version "1.0"

  @spec main([String.t()]) :: :ok | no_return()
  def main(arguments) do
    archive = archive!(arguments)

    unless File.regular?(archive) do
      System.halt(12)
    end

    request = request!()

    request
    |> response()
    |> Jason.encode!()
    |> IO.binwrite()
  end

  defp archive!(["--archive", archive]), do: archive
  defp archive!(_), do: System.halt(11)

  defp request! do
    case IO.binread(:line) do
      line when is_binary(line) -> Jason.decode!(line)
      _ -> System.halt(13)
    end
  end

  defp response(%{
         "claim" => %{"operation" => operation},
         "vector" => %{"id" => vector_id, "input" => input}
       }) do
    base = %{
      "protocol" => @protocol,
      "protocol_version" => @protocol_version,
      "vector_id" => vector_id
    }

    case observation(operation, input) do
      {:ok, actual} ->
        Map.merge(base, %{"outcome" => "observed", "actual" => actual})

      :unsupported ->
        Map.merge(base, %{"outcome" => "unsupported", "codes" => ["operation_not_implemented"]})
    end
  end

  defp response(_), do: System.halt(14)

  defp observation(operation, %{"document" => document, "projection" => projection})
       when is_map(document) and is_list(projection) do
    case apply_operation(operation, document) do
      {:ok, value, module} ->
        {:ok,
         %{
           "accepted" => true,
           "document" => project(module.to_map(value), projection)
         }}

      {:error, errors} ->
        {:ok, %{"accepted" => false, "errors" => normalize_errors(errors)}}

      :unsupported ->
        :unsupported
    end
  end

  defp observation(_, _), do: :unsupported

  defp apply_operation("thing_description.parse", document) do
    parse(document, ThingDescription)
  end

  defp apply_operation("thing_description.validate", document) do
    construct(document, ThingDescription)
  end

  defp apply_operation("thing_model.parse", document) do
    parse(document, ThingModel)
  end

  defp apply_operation("thing_model.validate", document) do
    construct(document, ThingModel)
  end

  defp apply_operation(_, _), do: :unsupported

  defp parse(document, module) do
    with {:ok, json} <- JSON.encode(document),
         {:ok, value} <- module.parse(json) do
      {:ok, value, module}
    end
  end

  defp construct(document, module) do
    case module.from_map(document) do
      {:ok, value} -> {:ok, value, module}
      {:error, errors} -> {:error, errors}
    end
  end

  defp project(document, pointers) do
    Map.new(pointers, fn pointer ->
      case JSON.resolve_pointer(document, pointer) do
        {:ok, value} -> {pointer, value}
        :error -> {pointer, nil}
      end
    end)
  end

  defp normalize_errors(%Error{} = error), do: normalize_errors([error])

  defp normalize_errors(errors) when is_list(errors) do
    errors
    |> Enum.map(fn %Error{} = error ->
      %{
        "code" => Atom.to_string(error.code),
        "phase" => Atom.to_string(error.phase),
        "path" => error.path
      }
    end)
    |> Enum.sort_by(&{&1["path"], &1["code"], &1["phase"]})
  end
end

Wotex.Check.WCFTarget.main(System.argv())
