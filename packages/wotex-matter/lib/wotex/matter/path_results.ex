defmodule Wotex.Matter.PathResults do
  @moduledoc """
  Validates and orders one untrusted batch-read result.

  The normalizer reconstructs concrete paths, attribute reports, and structured
  per-path errors returned by an explicitly selected client. It rejects
  duplicate or unrequested paths, requires every concrete request to have a
  result, orders wildcard expansions by numeric path, and enforces the aggregate
  result budget before returning data to `Wotex.Matter.read_paths/3`.
  """

  alias Wotex.Matter.{Address, AttributeReport, Error, ReadPath}

  @result_budget 98_304

  @doc "Normalizes a finite client result against the validated caller paths."
  @spec normalize([ReadPath.t()], term()) :: {:ok, [map()]} | {:error, Error.t()}
  def normalize(requested, results)
      when is_list(requested) and length(requested) in 1..64 and is_list(results) and
             length(results) <= 1024 do
    with {:ok, results} <- reconstruct(results, []),
         true <- unique_paths?(results),
         {:ok, ordered} <- order(requested, results),
         :ok <- within_budget(ordered) do
      {:ok, ordered}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  def normalize(_, _), do: {:error, Error.new(:invalid_transport_return)}

  defp reconstruct([], acc), do: {:ok, Enum.reverse(acc)}

  defp reconstruct([%{path: path, result: result} = entry | rest], acc)
       when map_size(entry) == 2 do
    with {:ok, path} <- Address.new(path),
         {:ok, result} <- result(path, result) do
      reconstruct(rest, [%{path: path, result: result} | acc])
    end
  end

  defp reconstruct(_, _), do: :error

  defp result(path, {:ok, report}) do
    with {:ok, report} <- AttributeReport.new(report),
         true <- report.path == path do
      {:ok, {:ok, report}}
    else
      _ -> :error
    end
  end

  defp result(_, {:error, %Error{} = error}) do
    if valid_error?(error), do: {:ok, {:error, error}}, else: :error
  end

  defp result(_, _), do: :error

  defp valid_error?(%Error{
         code: code,
         field: field,
         class: class,
         details: details,
         retryable: retryable,
         effect: :none
       }) do
    is_atom(code) and not is_nil(code) and valid_field?(field) and is_map(details) and
      valid_class?(class) and map_size(details) <= 16 and :erlang.external_size(details) <= 4096 and
      is_boolean(retryable)
  end

  defp valid_error?(_), do: false
  defp valid_field?(nil), do: true
  defp valid_field?(field), do: is_atom(field)

  defp valid_class?(class),
    do: class in [:timeout, :unavailable, :rate_limited, :protocol, :permanent, nil]

  defp unique_paths?(results) do
    paths = Enum.map(results, &path_key(&1.path))
    length(paths) == length(Enum.uniq(paths))
  end

  defp order(requested, results) do
    indexed = Enum.with_index(requested)

    with true <-
           Enum.all?(
             results,
             &Enum.any?(requested, fn request -> ReadPath.matches?(request, &1.path) end)
           ),
         true <- concrete_requests_present?(indexed, results) do
      ordered =
        Enum.flat_map(indexed, fn {_, index} ->
          results
          |> Enum.filter(&(owner_index(indexed, &1.path) == index))
          |> Enum.sort_by(&path_key(&1.path))
        end)

      if length(ordered) == length(results), do: {:ok, ordered}, else: :error
    else
      _ -> :error
    end
  end

  defp concrete_requests_present?(indexed, results) do
    Enum.all?(indexed, fn
      {%ReadPath{} = request, _} ->
        not ReadPath.concrete?(request) or
          Enum.any?(results, fn result -> ReadPath.matches?(request, result.path) end)
    end)
  end

  defp owner_index(indexed, address) do
    exact =
      Enum.find(indexed, fn {request, _} ->
        ReadPath.concrete?(request) and ReadPath.matches?(request, address)
      end)

    {_, index} =
      exact || Enum.find(indexed, fn {request, _} -> ReadPath.matches?(request, address) end)

    index
  end

  defp within_budget(results) do
    case Enum.reduce_while(results, 2, fn result, size ->
           case projected_size(result, size) do
             {:ok, next} -> {:cont, next}
             :error -> {:halt, :error}
           end
         end) do
      :error -> {:error, Error.new(:response_limit)}
      _ -> :ok
    end
  end

  defp projected_size(result, size) do
    with {:ok, encoded} <- Jason.encode_to_iodata(projection(result)),
         next = size + IO.iodata_length(encoded) + if(size == 2, do: 0, else: 1),
         true <- next <= @result_budget do
      {:ok, next}
    else
      _ -> :error
    end
  end

  defp projection(%{path: path, result: {:ok, report}}) do
    %{
      "path" => path_projection(path),
      "result" => %{
        "ok" => %{
          "path" => path_projection(report.path),
          "value" => element_projection(report.value),
          "data_version" => report.data_version
        }
      }
    }
  end

  defp projection(%{path: path, result: {:error, error}}) do
    %{
      "path" => path_projection(path),
      "result" => %{
        "error" => %{
          "code" => Atom.to_string(error.code),
          "field" => if(error.field, do: Atom.to_string(error.field)),
          "details" => error.details,
          "retryable" => error.retryable,
          "effect" => Atom.to_string(error.effect)
        }
      }
    }
  end

  defp path_projection(path) do
    %{
      "fabric_id" => path.fabric_id,
      "node_id" => path.node_id,
      "endpoint" => path.endpoint,
      "cluster" => path.cluster,
      "member" => path.member
    }
  end

  defp element_projection(%{tag: tag, type: :bytes, value: value}) do
    %{
      "tag" => tag_projection(tag),
      "type" => "bytes",
      "value" => %{"base64" => Base.encode64(value)}
    }
  end

  defp element_projection(%{tag: tag, type: type, value: value})
       when type in [:structure, :array, :list] do
    %{
      "tag" => tag_projection(tag),
      "type" => Atom.to_string(type),
      "value" => Enum.map(value, &element_projection/1)
    }
  end

  defp element_projection(%{tag: tag, type: type, value: value}) do
    %{"tag" => tag_projection(tag), "type" => Atom.to_string(type), "value" => value}
  end

  defp tag_projection(:anonymous), do: "anonymous"
  defp tag_projection(tag), do: Enum.map(Tuple.to_list(tag), &atom_string/1)
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_string(value), do: value
  defp path_key(path), do: {path.fabric_id, path.node_id, path.endpoint, path.cluster, path.member}
end
