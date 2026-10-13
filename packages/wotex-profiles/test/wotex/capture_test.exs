defmodule Wotex.Profiles.CaptureTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Capture, Error}
  alias Wotex.Profiles.Test.Fixtures, as: F

  test "independent capture identity survives all checked public seams" do
    data = F.json("capture")
    binding = F.json("installed-binding")
    assert {:ok, digest} = Capture.digest(Map.delete(data, "digest"), binding, F.limits())
    assert digest == data["digest"]
    assert {:ok, capture} = Capture.new(data, binding, F.limits())
    assert {:ok, ^capture} = Capture.new(capture, binding, F.limits())
    assert {:ok, ^data} = Capture.to_map(capture, binding, F.limits())
    assert {:error, %Error{}} = Capture.new(Map.put(capture, :extra, "secret"), binding, F.limits())
  end

  test "basis changes refuse before any fingerprint assumption" do
    data = F.json("capture")
    binding = F.json("installed-binding")

    for changed <- [
          Map.put(data, "capture_epoch", String.duplicate("a", 32)),
          put_in(data, ["fields", "model", "value"], "changed-model")
        ] do
      assert {:error, %Error{code: :stale_basis, path: "/capture/digest"}} =
               Capture.new(changed, binding, F.limits())

      assert {:ok, digest} = Capture.digest(Map.delete(changed, "digest"), binding, F.limits())
      assert {:ok, _} = Capture.new(Map.put(changed, "digest", digest), binding, F.limits())
    end

    assert {:error, %Error{code: :stale_basis, path: "/capture/binding"}} =
             Capture.new(
               put_in(data, ["binding", "sha256"], String.duplicate("c", 64)),
               binding,
               F.limits()
             )
  end

  test "field subsets are explicit, typed and bounded without foreign error payloads" do
    data = Map.delete(F.json("capture"), "digest")
    binding = F.json("installed-binding")

    for fields <- [
          %{},
          %{"model" => %{"type" => "boolean", "value" => true}},
          %{"model" => %{"type" => "sint", "value" => "-1"}},
          %{"model" => %{"type" => "uint", "value" => "1"}}
        ] do
      assert {:ok, _} = Capture.digest(Map.put(data, "fields", fields), binding, F.limits())
    end

    for fields <- [
          nil,
          %{"private-field-canary" => %{"type" => "text", "value" => "private-value-canary"}},
          %{"model" => "primitive"},
          %{"model" => %{"type" => "decimal", "coefficient" => "1", "exponent" => 0}},
          %{"model" => %{"type" => "bytes", "base64" => "AA=="}}
        ] do
      assert {:error, %Error{} = error} =
               Capture.digest(Map.put(data, "fields", fields), binding, F.limits())

      refute inspect(error) =~ "private-"
    end

    for epoch <- [nil, "", String.duplicate("A", 32), String.duplicate("a", 33)] do
      assert {:error, %Error{}} =
               Capture.digest(Map.put(data, "capture_epoch", epoch), binding, F.limits())
    end

    for bad <- [%{}, Map.put(data, "extra", 1), %{"binding" => %{}}] do
      assert {:error, %Error{}} = Capture.digest(bad, binding, F.limits())
    end

    assert {:error, %Error{}} = Capture.new(F.json("capture"), %{}, F.limits())

    assert {:error, %Error{}} =
             Capture.new(Map.put(F.json("capture"), "digest", "bad"), binding, F.limits())

    assert {:error, %Error{code: :input_limit}} =
             Capture.digest(data, binding, Map.put(F.limits(), "max_nodes", 1))
  end
end
