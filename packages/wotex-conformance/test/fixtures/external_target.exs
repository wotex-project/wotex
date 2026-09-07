defmodule ExternalTargetFixture do
  @moduledoc false

  # This fixture is an independent external target. It never looks a vector up
  # by identity and holds no table of expected answers. It derives one
  # normalized observation from the request alone: it decodes the declared
  # input document with the runtime JSON module, applies the declared
  # projection, and otherwise reports rejection errors produced by the
  # structural rules stated in `document_errors/2`. It proves the protocol,
  # projection, and classification mechanics; it is not a W3C validator and is
  # no evidence about any subject package.

  @context "https://www.w3.org/2022/wot/td/v1.1"
  @legacy_context "https://www.w3.org/2019/wot/td/v1"
  @model_type "tm:ThingModel"

  @spec run() :: :ok | no_return()
  def run do
    archive = archive_path(System.argv())

    if not File.regular?(archive) do
      System.halt(12)
    end

    verify_archive(archive)
    maybe_mark()
    respond(System.get_env("TARGET_MODE", "pass"))
  end

  defp respond("nonzero"), do: System.halt(7)

  defp respond("malformed"), do: IO.binwrite("not-json")

  defp respond("oversized") do
    "observed"
    |> base_response(%{"bytes" => String.duplicate("x", 8_192)})
    |> emit()
  end

  defp respond("chatter") do
    Enum.each(1..5_000, fn _chunk -> IO.binwrite(String.duplicate("x", 4_096)) end)
    Process.sleep(5_000)
  end

  defp respond("sleep") do
    "TARGET_SLEEP_MS" |> System.get_env("100") |> String.to_integer() |> Process.sleep()
    request() |> observed_response() |> emit()
  end

  defp respond("wrong_vector") do
    request()
    |> observed_response()
    |> Map.put("vector_id", "different.vector")
    |> emit()
  end

  defp respond("unsupported") do
    request = request()

    "unsupported"
    |> base_response(nil, request["vector"]["id"])
    |> Map.put("codes", ["operation_not_implemented"])
    |> emit()
  end

  defp respond("mismatch") do
    request()
    |> observed_response(%{
      "accepted" => false,
      "errors" => [%{"code" => "synthetic_mismatch", "phase" => "target", "path" => "/"}]
    })
    |> emit()
  end

  defp respond("unnormalized") do
    request()
    |> observed_response(%{"accepted" => "yes", "document" => "not-an-object"})
    |> emit()
  end

  defp respond("pass") do
    request() |> observed_response() |> emit()
  end

  defp archive_path(["--archive", path]), do: path
  defp archive_path(_args), do: System.halt(11)

  defp verify_archive(archive) do
    case :erl_tar.extract(String.to_charlist(archive), [:compressed, :memory]) do
      {:ok, [{~c"manifest.json", contents}]} ->
        case :json.decode(contents) do
          %{"interface_revision" => "1", "subject" => "synthetic"} -> :ok
          _manifest -> System.halt(15)
        end

      _result ->
        System.halt(16)
    end
  end

  # Raw bytes: the request carries UTF-8 that a latin1 standard input mangles.
  defp request do
    case IO.binread(:line) do
      :eof -> System.halt(13)
      {:error, _reason} -> System.halt(14)
      line -> :json.decode(line)
    end
  end

  defp observed_response(request) do
    observed_response(request, observation(request))
  end

  defp observed_response(request, observation) do
    actual =
      if hidden_runner_fields?(request) or System.get_env("WOTEX_CONFORMANCE_SHOULD_NOT_LEAK") do
        %{"request_boundary" => "violated"}
      else
        observation
      end

    base_response("observed", actual, request["vector"]["id"])
  end

  # The only inputs are the claim operation and the declared vector input.
  defp observation(request) do
    operation = request["claim"]["operation"]

    input =
      case request["vector"] do
        %{"input" => %{} = declared} -> declared
        _other -> %{}
      end

    document = Map.get(input, "document")

    case document_errors(operation, document) do
      [] ->
        %{"accepted" => true, "document" => project(document, Map.get(input, "projection", []))}

      errors ->
        %{"accepted" => false, "errors" => Enum.sort_by(errors, &{&1["path"], &1["code"]})}
    end
  end

  # Structural rules, applied to the declared document only.
  #
  #   * the document context must be the TD 1.1 context, optionally preceded
  #     by the TD 1.0 context;
  #   * a Thing Model must declare `tm:ThingModel`, and a Thing Description
  #     must not;
  #   * a document must carry a non-empty `title`; and
  #   * every security reference must name an entry of `securityDefinitions`.
  defp document_errors(operation, document) when is_map(document) do
    context_errors(Map.get(document, "@context")) ++
      type_errors(operation, Map.get(document, "@type")) ++
      title_errors(document) ++ security_errors(document)
  end

  defp document_errors(_operation, _document) do
    [error("object_required", "parse", "/")]
  end

  defp context_errors(@context), do: []
  defp context_errors([@context | _rest]), do: []
  defp context_errors([@legacy_context, @context | _rest]), do: []
  defp context_errors(_context), do: [error("unsupported_context", "semantic", "/@context")]

  defp type_errors("thing_model." <> _operation, type) do
    if @model_type in List.wrap(type),
      do: [],
      else: [error("schema_violation", "schema", "/@type")]
  end

  defp type_errors(_operation, type) do
    if @model_type in List.wrap(type),
      do: [error("thing_model_not_accepted", "semantic", "/@type")],
      else: []
  end

  defp title_errors(document) do
    case Map.get(document, "title") do
      title when is_binary(title) ->
        if String.trim(title) == "", do: [error("empty_title", "semantic", "/title")], else: []

      _missing ->
        [error("schema_violation", "schema", "/title")]
    end
  end

  defp security_errors(%{"securityDefinitions" => definitions} = document)
       when is_map(definitions) do
    document
    |> security_references()
    |> Enum.reject(fn {_path, reference} -> Map.has_key?(definitions, reference) end)
    |> Enum.map(fn {path, _reference} ->
      error("undefined_security_reference", "semantic", path)
    end)
  end

  defp security_errors(%{"security" => _security}) do
    [error("schema_violation", "schema", "/securityDefinitions")]
  end

  defp security_errors(_document), do: []

  defp security_references(document) do
    references(Map.get(document, "security"), "/security") ++
      form_references(Map.get(document, "forms"), "/forms") ++
      affordance_references(document) ++
      combo_references(Map.get(document, "securityDefinitions"))
  end

  defp affordance_references(document) do
    Enum.flat_map(~w(properties actions events), fn category ->
      document
      |> Map.get(category, %{})
      |> entries()
      |> Enum.flat_map(fn {name, affordance} ->
        path = "/#{category}/#{segment(name)}/forms"
        form_references(Map.get(affordance, "forms"), path)
      end)
    end)
  end

  defp form_references(forms, path) when is_list(forms) do
    forms
    |> Enum.with_index()
    |> Enum.flat_map(fn {form, index} ->
      references(Map.get(form, "security"), "#{path}/#{index}/security")
    end)
  end

  defp form_references(_forms, _path), do: []

  defp combo_references(definitions) when is_map(definitions) do
    definitions
    |> entries()
    |> Enum.flat_map(fn
      {name, %{"scheme" => "combo"} = definition} ->
        Enum.flat_map(~w(oneOf allOf), fn member ->
          references(Map.get(definition, member), "/securityDefinitions/#{segment(name)}/#{member}")
        end)

      {_name, _definition} ->
        []
    end)
  end

  defp combo_references(_definitions), do: []

  defp references(reference, path) when is_binary(reference), do: [{path, reference}]

  defp references(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {reference, index} when is_binary(reference) -> [{"#{path}/#{index}", reference}]
      {_reference, _index} -> []
    end)
  end

  defp references(_values, _path), do: []

  defp entries(value) when is_map(value), do: Enum.sort_by(value, &elem(&1, 0))
  defp entries(_value), do: []

  defp project(document, []), do: document

  defp project(document, pointers) when is_list(pointers) do
    Enum.reduce(pointers, %{}, fn pointer, projected ->
      case resolve(document, pointer) do
        {:ok, value} -> Map.put(projected, pointer, value)
        :error -> projected
      end
    end)
  end

  defp resolve(document, "/" <> pointer) do
    pointer
    |> String.split("/")
    |> Enum.reduce_while({:ok, document}, fn raw, {:ok, value} ->
      case member(value, unescape(raw)) do
        {:ok, member} -> {:cont, {:ok, member}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp resolve(_document, _pointer), do: :error

  defp member(value, segment) when is_map(value), do: Map.fetch(value, segment)

  defp member(value, segment) when is_list(value) do
    case Integer.parse(segment) do
      {index, ""} -> Enum.fetch(value, index)
      _other -> :error
    end
  end

  defp member(_value, _segment), do: :error

  defp unescape(segment), do: segment |> String.replace("~1", "/") |> String.replace("~0", "~")

  defp segment(name), do: name |> String.replace("~", "~0") |> String.replace("/", "~1")

  defp error(code, phase, path), do: %{"code" => code, "phase" => phase, "path" => path}

  defp hidden_runner_fields?(request) do
    forbidden = MapSet.new(~w(expectation expected_digest provenance vector_digest))
    contains_key?(request, forbidden)
  end

  defp contains_key?(value, forbidden) when is_map(value) do
    Enum.any?(value, fn {key, entry} ->
      MapSet.member?(forbidden, key) or contains_key?(entry, forbidden)
    end)
  end

  defp contains_key?(value, forbidden) when is_list(value) do
    Enum.any?(value, &contains_key?(&1, forbidden))
  end

  defp contains_key?(_value, _forbidden), do: false

  defp base_response(outcome, actual, vector_id \\ "unused") do
    response = %{
      "protocol" => "wotex.conformance.target",
      "protocol_version" => "1.0",
      "vector_id" => vector_id,
      "outcome" => outcome
    }

    if outcome == "observed", do: Map.put(response, "actual", actual), else: response
  end

  defp emit(response) do
    IO.binwrite(:json.encode(response))
  catch
    :error, :terminated -> :ok
  end

  defp maybe_mark do
    case System.get_env("TARGET_MARKER_PATH") do
      nil -> :ok
      path -> File.write!(path, "invoked")
    end
  end
end

ExternalTargetFixture.run()
