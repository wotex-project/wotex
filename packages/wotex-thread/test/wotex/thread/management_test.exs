defmodule Wotex.Thread.ManagementTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread
  alias Wotex.Thread.{Dataset, Error, Session, TestClient}
  alias Wotex.Thread.OpenThread.{Frame, Request}

  @moduletag requirements: ["WTH-S04", "WTH-C02", "WTH-C07"], vectors: ["WTH-V06"]

  test "management combines ordered TLVs within one bounded validated envelope" do
    {:ok, dataset} = Dataset.decode(<<250, 1, 42>>)

    for type <- [:management_active_set, :management_pending_set] do
      assert {:ok, {operation, %{dataset: %{base64: encoded, type: "bytes"}}}} =
               Request.encode(%{
                 type: type,
                 update: %{dataset: dataset, extra_tlvs: [{251, <<7>>}]}
               })

      assert operation == Atom.to_string(type)
      assert Base.decode64!(encoded) == <<250, 1, 42, 251, 1, 7>>
      assert Request.mutation?(operation)
      assert {:ok, _} = Request.encode(%{type: type, update: %{dataset: dataset}})
    end
  end

  test "forged, duplicate, oversized and improper extras never become commands" do
    {:ok, dataset} = Dataset.decode(<<250, 1, 42>>)

    for update <- [
          nil,
          %{dataset: nil},
          %{dataset: Map.put(dataset, :extra, true)},
          %{dataset: dataset, extra: true},
          %{dataset: dataset, extra_tlvs: nil},
          %{dataset: dataset, extra_tlvs: [{251, <<>>} | :tail]},
          %{dataset: dataset, extra_tlvs: [{250, <<>>}]},
          %{dataset: dataset, extra_tlvs: [{251, <<>>}, {251, <<>>}]},
          %{dataset: dataset, extra_tlvs: [{256, <<>>}]},
          %{dataset: dataset, extra_tlvs: [{-1, <<>>}]},
          %{dataset: dataset, extra_tlvs: [{251, :bad}]},
          %{dataset: dataset, extra_tlvs: [{251, :binary.copy(<<0>>, 250)}]},
          %{dataset: dataset, extra_tlvs: [{0, <<>>}]}
        ] do
      assert {:error, %Error{}} = Request.encode(%{type: :management_active_set, update: update})
    end

    assert {:error, %Error{code: :invalid_message}} =
             Request.encode(%{
               type: :management_active_set,
               update: %{dataset: dataset},
               extra: true
             })

    assert {:ok, _} =
             Request.encode(%{
               type: :management_pending_set,
               update: %{dataset: dataset, extra_tlvs: [{251, :binary.copy(<<0>>, 249)}]}
             })
  end

  test "acceptance has an exact result and never implies effectiveness" do
    for operation <- ["management_active_set", "management_pending_set"] do
      valid = %{"accepted" => true, "effective" => "not_verified"}
      assert {:ok, %{accepted: true, effective: :not_verified}} = reply(valid, operation)

      for invalid <- [
            nil,
            true,
            %{},
            Map.put(valid, "extra", true),
            Map.put(valid, "accepted", false),
            Map.put(valid, "effective", "verified")
          ] do
        assert :invalid = reply(invalid, operation)
      end

      frame = %{
        "version" => 1,
        "id" => "1",
        "ok" => false,
        "error" => %{"code" => "management_timeout"}
      }

      assert {:error, %Error{code: :management_timeout}} = Frame.response(frame, "1", operation)
    end
  end

  test "custom clients cannot execute SDK management, and invalid data has no effect" do
    {:ok, dataset} = Dataset.decode(<<250, 1, 42>>)
    session = %Session{client: TestClient, handle: :unavailable, timeout: 1000}

    for operation <- [:management_active_set, :management_pending_set] do
      assert {:error, %Error{code: :not_supported, effect: :none}} =
               apply(Thread, operation, [session, %{dataset: dataset}, 1000])

      assert {:error, %Error{effect: :none}} = apply(Thread, operation, [session, nil, 1000])
    end
  end

  defp reply(value, operation),
    do:
      Frame.response(
        %{"version" => 1, "id" => "1", "ok" => true, "result" => value},
        "1",
        operation
      )
end
