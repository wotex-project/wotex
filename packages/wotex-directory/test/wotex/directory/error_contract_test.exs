defmodule Wotex.Directory.ErrorContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory
  alias Wotex.Directory.{Context, Error, Fixtures, MemoryRepository, Query, TestService}

  test "public operations reject invalid service and request shapes deterministically" do
    thing_description = Fixtures.thing_description("urn:example:thing:1")
    context = Context.new!(:principal)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.register(:invalid, thing_description, context)

    assert {:error, %Error{code: :invalid_request}} = Directory.get(:invalid, "urn:x", context)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.replace(:invalid, "urn:x", thing_description, context)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.patch(:invalid, "urn:x", %{}, context)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.delete(:invalid, "urn:x", context)

    assert {:error, %Error{code: :invalid_request}} = Directory.list(:invalid, context)
    query = %Query{profile: :listing, limit: 1, format: :array}
    assert {:error, %Error{code: :invalid_request}} = Directory.query(:invalid, query, context)
    assert {:error, %Error{code: :invalid_request}} = Directory.expire(:invalid, context)
    assert {:error, %Error{code: :invalid_service}} = Directory.introduction(:invalid)
  end

  test "operations reject invalid context, identifier, options, patch, and version values" do
    existing = create_entry("urn:example:thing:1")
    setup = TestService.build(entries: [existing])
    invalid_context = %Context{principal: nil}
    thing_description = Fixtures.thing_description(existing.identifier)

    assert {:error, %Error{code: :invalid_context}} =
             Directory.get(setup.service, existing.identifier, invalid_context)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.get(setup.service, "relative", setup.context)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.register(setup.service, thing_description, setup.context, unknown: true)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.replace(
               setup.service,
               existing.identifier,
               thing_description,
               setup.context,
               if_version: 0
             )

    assert {:error, %Error{code: :invalid_request}} =
             Directory.patch(
               setup.service,
               existing.identifier,
               :not_a_map,
               setup.context
             )

    assert {:error, %Error{code: :invalid_request}} =
             Directory.delete(setup.service, existing.identifier, setup.context, unknown: true)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.expire(setup.service, setup.context, limit: 0)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.expire(setup.service, setup.context, strategy: :unknown)
  end

  test "registration rejects ambiguous out-of-band and enriched metadata" do
    setup = TestService.build()

    enriched =
      Fixtures.thing_description("urn:example:thing:1", %{
        "@context" => [
          Wotex.td_context_1_1(),
          "https://www.w3.org/2022/wot/discovery"
        ],
        "registration" => %{"ttl" => 60}
      })

    assert {:error, %Error{code: :invalid_request}} =
             Directory.register(
               setup.service,
               enriched,
               setup.context,
               registration: %{"ttl" => 120}
             )

    assert {:error, %Error{code: :invalid_request}} =
             Directory.register(
               setup.service,
               Fixtures.thing_description("urn:example:thing:2"),
               setup.context,
               registration: :invalid
             )

    assert MemoryRepository.entries(setup.repository) == %{}
  end

  test "maps explicit authorization variants and port result failures" do
    thing_description = Fixtures.thing_description("urn:example:thing:1")

    forbidden = TestService.build(authorization: %{result: {:error, :forbidden}})

    assert {:error, %Error{code: :forbidden}} =
             Directory.register(forbidden.service, thing_description, forbidden.context)

    invalid_authorization = TestService.build(authorization: %{result: :invalid})

    assert {:error, %Error{code: :authorization_failure}} =
             Directory.list(invalid_authorization.service, invalid_authorization.context)

    identifier_failure = TestService.build(identifiers: [{:error, :unavailable}])

    assert {:error, %Error{code: :identifier_failure}} =
             Directory.register(
               identifier_failure.service,
               Fixtures.thing_description(nil),
               identifier_failure.context
             )

    invalid_identifier_result = TestService.build(identifiers: [])

    assert {:error, %Error{code: :identifier_failure}} =
             Directory.register(
               invalid_identifier_result.service,
               Fixtures.thing_description(nil),
               invalid_identifier_result.context
             )
  end

  test "rejects invalid core values and bounded merge patches without repository writes" do
    existing = create_entry("urn:example:thing:1")
    setup = TestService.build(entries: [existing], max_patch_depth: 2, max_patch_nodes: 3)
    {:ok, invalid} = Wotex.ThingDescription.from_map(%{}, validate: false)

    assert {:error, %Error{code: :invalid_thing_description}} =
             Directory.register(setup.service, invalid, setup.context)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.patch(
               setup.service,
               existing.identifier,
               %{"a" => %{"b" => %{"c" => true}}},
               setup.context
             )

    refute Enum.any?(MemoryRepository.calls(setup.repository), &match?({:replace, _, _, _}, &1))
  end

  test "core limits bound admission before any repository write" do
    setup = TestService.build(thing_description_options: [max_string_bytes: 8])

    assert {:error, %Error{code: :invalid_thing_description, phase: :validation}} =
             Directory.register(
               setup.service,
               Fixtures.thing_description("urn:example:thing:1"),
               setup.context
             )

    assert MemoryRepository.entries(setup.repository) == %{}
  end

  test "every public failure carries the family error shape" do
    existing = create_entry("urn:example:thing:1")
    setup = TestService.build(entries: [existing])
    expired = TestService.build(authorization: %{result: :deny})

    failures = [
      Directory.get(setup.service, "relative", setup.context),
      Directory.get(expired.service, existing.identifier, expired.context),
      Directory.get(setup.service, "urn:example:missing", setup.context),
      Directory.patch(setup.service, existing.identifier, %{"title" => nil}, setup.context),
      Directory.patch(
        setup.service,
        existing.identifier,
        %{"registration" => %{"created" => "2030-01-01T00:00:00Z"}},
        setup.context
      ),
      Directory.expire(setup.service, setup.context, limit: 0),
      Directory.introduction(:invalid)
    ]

    for {:error, error} <- failures do
      assert error.code in codes()
      assert error.phase in phases()
      assert is_binary(error.message)
      assert error.message == Error.message_for(error.code)
      assert is_map(error.details)
      assert Map.has_key?(error.details, :operation)
      assert is_nil(error.path) or String.starts_with?(error.path, "/")
    end

    assert {:error, %Error{phase: :patch, path: "/registration"}} =
             Directory.patch(
               setup.service,
               existing.identifier,
               %{"registration" => %{"modified" => nil}},
               setup.context
             )
  end

  defp codes do
    [
      :invalid_service,
      :invalid_context,
      :invalid_request,
      :invalid_thing_description,
      :identifier_mismatch,
      :not_found,
      :expired,
      :forbidden,
      :conflict,
      :collection_changed,
      :unsupported_query_profile,
      :invalid_page,
      :authorization_failure,
      :repository_failure,
      :clock_failure,
      :clock_regression,
      :identifier_failure
    ]
  end

  defp phases do
    [
      :configuration,
      :validation,
      :authorization,
      :clock,
      :identifier,
      :repository,
      :listing,
      :patch,
      :expiry
    ]
  end

  defp create_entry(identifier) do
    now = ~U[2026-09-02 10:00:00Z]
    {:ok, registration} = Wotex.Directory.Registration.create(now, :absent, :register)

    {:ok, entry} =
      Wotex.Directory.Entry.new(identifier, Fixtures.thing_description(identifier), registration)

    entry
  end
end
