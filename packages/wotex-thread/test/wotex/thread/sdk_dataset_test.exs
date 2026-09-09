defmodule Wotex.Thread.SdkDatasetTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread
  alias Wotex.Thread.{Dataset, Error, Session, TestClient}
  alias Wotex.Thread.OpenThread.{Frame, Request}

  @moduletag requirements: ["WTH-S01", "WTH-C02", "WTH-C07"], vectors: ["WTH-V02"]

  test "Dataset commands have exact selectors and binary envelopes" do
    {:ok, dataset} = Dataset.decode(<<250, 1, 0>>)

    assert {:ok, {"validate_dataset", %{kind: "active", dataset: %{type: "bytes", base64: "+gEA"}}}} =
             Request.encode(%{type: :validate_dataset, dataset: dataset, kind: :active})

    assert {:ok, {"get_dataset", %{kind: "pending"}}} =
             Request.encode(%{type: :get_dataset, kind: :pending})

    for message <- [
          %{type: :get_dataset, kind: :active, extra: true},
          %{type: :validate_dataset, dataset: dataset},
          %{type: :get_dataset},
          %{type: :validate_dataset, dataset: dataset, kind: :active, extra: true}
        ] do
      assert {:error, %Error{code: :invalid_message}} = Request.encode(message)
    end
  end

  test "native Dataset functions reject borrowed clients and forged requests before dispatch" do
    {:ok, dataset} = Dataset.decode(<<250, 1, 0>>)
    session = %Session{client: TestClient, handle: :unavailable, timeout: 1000}

    assert {:error, %Error{code: :not_supported}} =
             Thread.validate_dataset(session, dataset, :active, 1000)

    assert {:error, %Error{code: :not_supported}} = Thread.get_dataset(session, :pending, 1000)
    assert {:error, %Error{code: :invalid_dataset_kind}} = Thread.get_dataset(session, :bad, 1000)

    assert {:error, %Error{code: :invalid_dataset}} =
             Thread.validate_dataset(session, nil, :active, 1000)

    assert {:error, %Error{code: :invalid_options}} =
             Thread.get_dataset(session, :active, :infinity)

    assert {:error, %Error{code: :invalid_session}} = Thread.get_dataset(nil, :active, 1000)
  end

  test "Dataset reply validation rejects malformed bytes and success values" do
    frame = %{"version" => 1, "id" => "1", "ok" => true, "result" => nil}
    assert {:ok, nil} = Frame.response(frame, "1", "validate_dataset")
    assert :invalid = Frame.response(%{frame | "result" => true}, "1", "validate_dataset")

    assert :invalid =
             Frame.response(
               %{frame | "result" => %{"type" => "bytes", "base64" => "AB=="}},
               "1",
               "get_dataset"
             )

    assert {:ok, %Dataset{entries: [{250, <<0>>}]}} =
             Frame.response(
               %{frame | "result" => %{"type" => "bytes", "base64" => "+gEA"}},
               "1",
               "get_dataset"
             )
  end
end
