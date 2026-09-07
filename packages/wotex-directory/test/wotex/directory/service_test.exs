defmodule Wotex.Directory.ServiceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory.{Context, Error, Fixtures, Service, TestAuthorization}
  alias Wotex.Directory.{TestClock, TestIdentifier}

  defmodule MissingRepositoryCallbacks do
    @moduledoc false
  end

  test "requires every explicit port and a valid Introduction Thing Description" do
    assert {:error, %Error{code: :invalid_service}} = Service.new([])

    options = valid_options()

    assert {:error, %Error{code: :invalid_service, details: %{port: :repository}}} =
             options
             |> Keyword.put(:repository, {MissingRepositoryCallbacks, nil})
             |> Service.new()

    assert {:error, %Error{code: :invalid_service}} =
             options
             |> Keyword.put(:introduction, :not_a_thing_description)
             |> Service.new()
  end

  test "rejects inverted, zero, and unknown service configuration" do
    options = valid_options()

    assert {:error, %Error{code: :invalid_service}} =
             options
             |> Keyword.put(:default_page_limit, 5)
             |> Keyword.put(:max_page_limit, 4)
             |> Service.new()

    assert {:error, %Error{code: :invalid_service}} =
             options
             |> Keyword.put(:max_patch_nodes, 0)
             |> Service.new()

    assert {:error, %Error{code: :invalid_service}} =
             options
             |> Keyword.put(:thing_description_options, validate: false)
             |> Service.new()

    assert {:error, %Error{code: :invalid_service}} =
             options
             |> Keyword.put(:unknown, true)
             |> Service.new()
  end

  test "the shipped system clock is selected explicitly and never implicitly" do
    options = valid_options()

    assert {:ok, service} =
             options |> Keyword.put(:clock, {Wotex.Directory.Clock.System, nil}) |> Service.new()

    assert service.clock == {Wotex.Directory.Clock.System, nil}

    assert {:ok, default} = Service.new(options)
    assert default.clock == Keyword.fetch!(options, :clock)
  end

  test "accepts the core limit vocabulary and rejects every invalid limit" do
    options = valid_options()

    limits = [
      max_bytes: 4_096,
      max_depth: 32,
      max_nodes: 5_000,
      max_string_bytes: 1_024,
      max_collection_size: 64
    ]

    assert {:ok, service} =
             options |> Keyword.put(:thing_description_options, limits) |> Service.new()

    assert service.thing_description_options == limits

    for invalid <- [
          [max_string_bytes: 0],
          [max_collection_size: -1],
          [max_bytes: :large],
          [validate: false],
          :not_a_keyword
        ] do
      assert {:error,
              %Error{
                code: :invalid_service,
                phase: :configuration,
                details: %{field: :thing_description_options}
              }} = options |> Keyword.put(:thing_description_options, invalid) |> Service.new()
    end
  end

  test "constructs context values without interpreting opaque consumer state" do
    assert {:ok, context} =
             Context.new(:principal, authorization: %{role: :reader}, repository: {:scope, 1})

    assert context.principal == :principal
    assert context.authorization == %{role: :reader}
    assert context.repository == {:scope, 1}

    assert {:error, %Error{code: :invalid_context}} = Context.new(nil)
    assert {:error, %Error{code: :invalid_context}} = Context.new(:principal, unknown: true)
  end

  defp valid_options do
    identifier_state = self()

    [
      repository: {Wotex.Directory.MemoryRepository, self()},
      authorization: {TestAuthorization, %{}},
      clock: {TestClock, ~U[2026-09-02 10:00:00Z]},
      identifier: {TestIdentifier, identifier_state},
      introduction: Fixtures.thing_description("urn:example:directory")
    ]
  end
end
