defmodule Wotex.Runtime.ValueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Runtime.{BindingProfile, Context, Error, Result, Retry}

  test "context accepts caller identity, deadline, and metadata without generating values" do
    deadline = DateTime.from_unix!(1_700_000_000)

    assert {:ok, context} =
             Context.new(request_id: "req-1", deadline: deadline, metadata: %{trace: "trace-1"})

    assert Context.request_id(context) == "req-1"
    assert Context.deadline(context) == deadline
    assert Context.metadata(context) == %{trace: "trace-1"}
    assert %Context{} = Context.new!(request_id: "req-2", deadline: 42)
  end

  test "context rejects invalid inputs and raising construction uses the same error" do
    assert {:error, %Error{code: :invalid_request_id}} = Context.new([])

    assert {:error, %Error{code: :invalid_deadline}} =
             Context.new(request_id: "req", deadline: :soon)

    assert {:error, %Error{code: :invalid_metadata}} = Context.new(request_id: "req", metadata: [])
    assert {:error, %Error{code: :invalid_context_options}} = Context.new(%{})
    assert_raise Error, fn -> Context.new!(request_id: "") end
  end

  test "binding profiles normalize declarations and match media type parameters" do
    assert {:ok, profile} =
             BindingProfile.new(
               id: "http",
               schemes: ["HTTPS"],
               operations: ["readproperty", :writeproperty],
               media_types: ["Application/JSON"]
             )

    assert BindingProfile.id(profile) == "http"
    assert BindingProfile.supports_scheme?(profile, "https")
    assert BindingProfile.supports_operation?(profile, :readproperty)
    assert BindingProfile.supports_media_type?(profile, "application/json; charset=utf-8")
    assert BindingProfile.supports_media_type?(profile, nil)
    refute BindingProfile.supports_operation?(profile, :invokeaction)
  end

  test "binding profiles reject incomplete and unsupported declarations" do
    assert {:error, %Error{code: :invalid_profile_id}} =
             BindingProfile.new(id: nil, schemes: ["https"], operations: [:readproperty])

    assert {:error, %Error{code: :invalid_profile_schemes}} =
             BindingProfile.new(id: :x, schemes: [], operations: [:readproperty])

    assert {:error, %Error{code: :invalid_profile_operations}} =
             BindingProfile.new(id: :x, schemes: ["https"], operations: [:invented])

    assert {:error, %Error{code: :invalid_profile_operations}} =
             BindingProfile.new(id: :x, schemes: ["https"], operations: :all)

    assert {:error, %Error{code: :invalid_profile_media_types}} =
             BindingProfile.new(
               id: :x,
               schemes: ["https"],
               operations: [:readproperty],
               media_types: :any
             )

    assert {:error, %Error{code: :invalid_profile_options}} = BindingProfile.new(%{})
  end

  test "an empty media-type declaration accepts transport defaults and wildcard accepts all" do
    assert {:ok, any_default} =
             BindingProfile.new(id: :a, schemes: ["https"], operations: [:readproperty])

    assert BindingProfile.supports_media_type?(any_default, "application/cbor")

    assert {:ok, wildcard} =
             BindingProfile.new(
               id: :b,
               schemes: ["https"],
               operations: [:readproperty],
               media_types: ["*/*"]
             )

    assert BindingProfile.supports_media_type?(wildcard, "application/cbor")
  end

  test "protocol results validate request identity, operation, and metadata" do
    assert {:ok, result} = Result.new("req", :readproperty, 21.5, status: 200)
    assert result.payload == 21.5
    assert result.status == 200

    assert {:error, %Error{code: :invalid_result_metadata}} =
             Result.new("req", :readproperty, nil, metadata: [])

    assert {:error, %Error{code: :invalid_result}} = Result.new("", :unknown, nil)
  end

  test "retry classification is pure and conservative for non-idempotent operations" do
    assert Retry.decision(:readproperty, :timeout) == :stop

    assert Retry.decision(:readproperty, :timeout, attempt: 1, max_attempts: 2, delay: 25) ==
             {:retry, 25}

    assert Retry.decision(:invokeaction, :timeout, attempt: 1, max_attempts: 2) == :stop

    assert Retry.decision(:invokeaction, :unavailable,
             attempt: 1,
             max_attempts: 2,
             delay: 0,
             idempotent?: true
           ) == {:retry, 0}

    assert Retry.decision(:readproperty, :invalid, attempt: 1, max_attempts: 3) == :stop
    assert Retry.decision(:readproperty, :timeout, attempt: 3, max_attempts: 3) == :stop
  end
end
