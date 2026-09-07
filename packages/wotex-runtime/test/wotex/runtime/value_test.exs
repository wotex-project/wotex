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
    assert {:ok, result} = Result.new("req", :readproperty, 21.5, metadata: %{http: %{status: 200}})
    assert result.payload == 21.5
    assert result.status == :ok

    assert {:ok, accepted} = Result.new("req", :invokeaction, nil, status: :accepted)
    assert accepted.status == :accepted

    assert {:error, %Error{code: :invalid_result_status}} =
             Result.new("req", :readproperty, nil, status: 200)

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

  test "retry classification accepts a classified runtime error" do
    unclassified = Error.new(:transport_request_failed, :transport, "failed")
    assert Error.class(unclassified) == nil
    assert Retry.decision(:readproperty, unclassified, attempt: 1, max_attempts: 3) == :stop

    classified = %{unclassified | class: :unavailable}

    assert Retry.decision(:readproperty, classified, attempt: 1, max_attempts: 3, delay: 5) ==
             {:retry, 5}
  end

  test "deadline budgets are computed from a caller-supplied clock reading" do
    assert Context.remaining_ms(nil, 0) == :infinity
    assert Context.remaining_ms(1_500, 1_000) == 500
    assert Context.remaining_ms(1_000, 1_500) == 0

    later = DateTime.add(~U[2026-09-07 12:00:00Z], 2, :second)
    assert Context.remaining_ms(later, ~U[2026-09-07 12:00:00Z]) == 2_000
    assert Context.remaining_ms(later, 0) == {:error, :clock_mismatch}
  end
end
