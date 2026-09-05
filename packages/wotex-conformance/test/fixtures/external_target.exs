defmodule ExternalTargetFixture do
  @moduledoc false

  @spec run() :: :ok | no_return()
  def run do
    archive = archive_path(System.argv())

    if not File.regular?(archive) do
      System.halt(12)
    end

    verify_archive(archive)

    maybe_mark()

    case System.get_env("TARGET_MODE", "pass") do
      "nonzero" ->
        System.halt(7)

      "malformed" ->
        IO.binwrite("not-json")

      "oversized" ->
        base_response("observed", %{"bytes" => String.duplicate("x", 8_192)})
        |> emit()

      "sleep" ->
        System.get_env("TARGET_SLEEP_MS", "100")
        |> String.to_integer()
        |> Process.sleep()

        request() |> passing_response() |> emit()

      "wrong_vector" ->
        request()
        |> passing_response()
        |> Map.put("vector_id", "different.vector")
        |> emit()

      "unsupported" ->
        request()
        |> then(fn request -> base_response("unsupported", nil, request["vector"]["id"]) end)
        |> Map.put("codes", ["operation_not_implemented"])
        |> emit()

      "mismatch" ->
        request()
        |> then(fn request ->
          base_response("observed", %{"unexpected" => true}, request["vector"]["id"])
        end)
        |> emit()

      "pass" ->
        request()
        |> passing_response()
        |> emit()
    end
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

  defp request do
    case IO.read(:line) do
      :eof -> System.halt(13)
      {:error, _reason} -> System.halt(14)
      line -> :json.decode(line)
    end
  end

  defp passing_response(request) do
    actual =
      if hidden_runner_fields?(request) or System.get_env("WOTEX_CONFORMANCE_SHOULD_NOT_LEAK") do
        %{"request_boundary" => "violated"}
      else
        expected_observation(request["vector"]["id"])
      end

    base_response("observed", actual, request["vector"]["id"])
  end

  defp expected_observation("td11.parse.affordance-categories") do
    %{"actions" => ["reset"], "events" => ["changed"], "properties" => ["level"]}
  end

  defp expected_observation("td11.parse.action-input-output") do
    %{
      "forms" => [%{"href" => "https://example.test/actions/setLevel", "op" => ["invokeaction"]}],
      "idempotent" => true,
      "input" => %{"maximum" => 100, "minimum" => 0, "type" => "integer"},
      "name" => "setLevel",
      "output" => %{"type" => "boolean"},
      "safe" => false
    }
  end

  defp expected_observation("td11.parse.event-data") do
    %{
      "data" => %{
        "properties" => %{
          "message" => %{"type" => "string"},
          "severity" => %{"type" => "integer"}
        },
        "type" => "object"
      },
      "forms" => [%{"href" => "https://example.test/events/alarm", "op" => ["subscribeevent"]}],
      "name" => "alarm"
    }
  end

  defp expected_observation("td11.parse.extension-preservation") do
    %{"accepted" => true, "extension" => %{"example:profile" => "synthetic"}}
  end

  defp expected_observation("td11.parse.minimal") do
    %{
      "accepted" => true,
      "context" => "https://www.w3.org/2022/wot/td/v1.1",
      "id" => "urn:example:thing:minimal",
      "title" => "Minimal Thing"
    }
  end

  defp expected_observation("td11.parse.multilingual-metadata") do
    %{
      "descriptions" => %{
        "en" => "Reports local conditions",
        "sv" => "Rapporterar lokala förhållanden"
      },
      "titles" => %{"en" => "Weather Thing", "sv" => "Väderting"}
    }
  end

  defp expected_observation("td11.parse.property-form") do
    %{
      "forms" => [
        %{
          "contentType" => "application/json",
          "href" => "https://example.test/properties/temperature",
          "op" => ["readproperty"]
        }
      ],
      "name" => "temperature",
      "readOnly" => true,
      "type" => "number",
      "unit" => "Cel"
    }
  end

  defp expected_observation("td11.parse.security-definition") do
    %{
      "security" => ["basic_sc"],
      "securityDefinitions" => %{"basic_sc" => %{"in" => "header", "scheme" => "basic"}}
    }
  end

  defp expected_observation("td11.parse.thing-level-form") do
    %{
      "forms" => [
        %{
          "contentType" => "application/json",
          "href" => "https://example.test/properties",
          "op" => ["readallproperties", "writeallproperties"]
        }
      ]
    }
  end

  defp expected_observation("td11.validate.missing-security-definitions") do
    %{"accepted" => false, "code" => "missing_required_security_definitions"}
  end

  defp expected_observation("td11.validate.missing-title") do
    %{"accepted" => false, "code" => "missing_required_title"}
  end

  defp expected_observation("td11.validate.undefined-combo-security-reference") do
    %{"accepted" => false, "code" => "undefined_security_reference"}
  end

  defp expected_observation("td11.validate.undefined-form-security-reference") do
    %{"accepted" => false, "code" => "undefined_security_reference"}
  end

  defp expected_observation("td11.validate.undefined-security-reference") do
    %{"accepted" => false, "code" => "undefined_security_reference"}
  end

  defp expected_observation(_vector_id), do: %{"unknown" => true}

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
