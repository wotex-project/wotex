defmodule WotexLabWorkbench.InvestigationOllamaTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias WotexLabWorkbench.Investigation.Ollama

  setup do
    Application.put_env(:wotex_lab_workbench, :beamlens_req_options, plug: {Req.Test, __MODULE__})

    on_exit(fn -> Application.delete_env(:wotex_lab_workbench, :beamlens_req_options) end)
    :ok
  end

  test "preflight requires the configured fixed model" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/v1/models"

      Req.Test.json(conn, %{
        "data" => [%{"id" => "qwen3.5:4b-q4_K_M"}, %{"id" => "another-model"}]
      })
    end)

    assert {:ok, %{model: "qwen3.5:4b-q4_K_M"}} = Ollama.preflight()
  end

  test "preflight refuses a substitute model" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

    assert {:error, {:ollama_model_missing, "qwen3.5:4b-q4_K_M"}} = Ollama.preflight()
  end

  test "completion is non-streaming, no-thinking and output-bounded" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)

      assert request["model"] == "qwen3.5:4b-q4_K_M"
      assert request["stream"] == false
      assert request["reasoning_effort"] == "none"
      assert request["max_tokens"] == 320
      assert request["messages"] == [%{"role" => "user", "content" => "diagnose"}]

      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "local diagnosis"}}]
      })
    end)

    assert {:ok, "local diagnosis", %{provider: :ollama, model: "qwen3.5:4b-q4_K_M"}} =
             Ollama.complete([%{"role" => "user", "content" => "diagnose"}])
  end

  test "malformed and non-success responses are failures, not empty answers" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"choices" => []}) end)
    assert {:error, :invalid_ollama_response} = Ollama.complete([])

    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 503, "offline") end)
    assert {:error, {:ollama_http_status, 503}} = Ollama.complete([])
  end
end
