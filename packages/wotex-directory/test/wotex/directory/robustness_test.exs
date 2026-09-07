defmodule Wotex.Directory.RobustnessTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory
  alias Wotex.Directory.{Entry, Error, Fixtures, Query, Registration, Service}
  alias Wotex.Directory.{StubRepository, TestService, ThingDescriptions}

  @now ~U[2026-09-02 10:00:00Z]

  describe "public boundary failures" do
    test "every operation rejects malformed service, context, and options deterministically" do
      setup = TestService.build()
      thing = Fixtures.thing_description()

      assert_error(:invalid_request, Directory.register(:invalid, thing, setup.context))
      assert_error(:invalid_request, Directory.register(setup.service, thing, :invalid))

      assert_error(
        :invalid_request,
        Directory.register(setup.service, thing, setup.context, [:bad])
      )

      assert_error(
        :invalid_request,
        Directory.get(:invalid, "urn:example:thing:1", setup.context)
      )

      assert_error(:invalid_request, Directory.get(setup.service, :invalid, setup.context))

      assert_error(
        :invalid_request,
        Directory.replace(:invalid, "urn:example:thing:1", thing, setup.context)
      )

      assert_error(
        :invalid_request,
        Directory.patch(:invalid, "urn:example:thing:1", %{}, setup.context)
      )

      assert_error(
        :invalid_request,
        Directory.delete(:invalid, "urn:example:thing:1", setup.context)
      )

      assert_error(:invalid_request, Directory.list(:invalid, setup.context))
      query = %Query{profile: :listing, limit: 1, format: :array}
      assert_error(:invalid_request, Directory.query(:invalid, query, setup.context))
      assert_error(:invalid_request, Directory.expire(:invalid, setup.context))
      assert_error(:invalid_service, Directory.introduction(:invalid))
    end

    test "invalid consumer callback results are redacted" do
      setup = TestService.build(authorization: %{result: :unexpected})

      assert_error(:authorization_failure, Directory.list(setup.service, setup.context))

      invalid_clock = %{setup.service | clock: {Wotex.Directory.TestClock, {:error, :private}}}

      allowed = %{
        setup.service
        | authorization: {Wotex.Directory.TestAuthorization, %{result: :ok}}
      }

      invalid_clock = %{allowed | clock: invalid_clock.clock}

      assert_error(:clock_failure, Directory.list(invalid_clock, setup.context))
    end

    test "repository result variants are normalized and never escape" do
      setup = TestService.build()
      thing = Fixtures.thing_description()

      for result <- [:unexpected, {:ok, :not_an_entry}, {:error, :not_found}] do
        service = repository(setup.service, %{fetch: result})
        expected = if result == {:error, :not_found}, do: :not_found, else: :repository_failure
        assert_error(expected, Directory.get(service, "urn:example:thing:1", setup.context))
      end

      anonymous = Fixtures.thing_description(nil)

      for result <- [{:error, :conflict}, {:error, :private}, :unexpected] do
        isolated = TestService.build()
        service = repository(isolated.service, %{insert: result})

        assert_error(
          result_code(result),
          Directory.register(service, anonymous, isolated.context)
        )
      end

      existing = entry()

      for result <- [{:error, :conflict}, {:error, :not_found}, {:error, :private}, :unexpected] do
        service = repository(setup.service, %{fetch: {:ok, existing}, replace: result})

        assert_error(
          replace_code(result),
          Directory.replace(service, existing.identifier, thing, setup.context)
        )
      end

      for result <- [{:error, :conflict}, {:error, :not_found}, {:error, :private}, :unexpected] do
        service = repository(setup.service, %{fetch: {:ok, existing}, delete: result})

        assert_error(
          delete_code(result),
          Directory.delete(service, existing.identifier, setup.context)
        )
      end

      for result <- [{:error, :private}, :unexpected] do
        list_service = repository(setup.service, %{list: result})
        assert_error(:repository_failure, Directory.list(list_service, setup.context))

        expire_service = repository(setup.service, %{expire_due: result})
        assert_error(:repository_failure, Directory.expire(expire_service, setup.context))
      end
    end

    test "invalid registration and expiry controls fail before persistence" do
      setup = TestService.build()
      thing = Fixtures.thing_description()

      assert_error(
        :invalid_request,
        Directory.register(setup.service, thing, setup.context, registration: :invalid)
      )

      assert_error(:invalid_request, Directory.expire(setup.service, setup.context, limit: 0))

      assert_error(
        :invalid_request,
        Directory.expire(setup.service, setup.context, strategy: :archive)
      )
    end
  end

  describe "Thing Description boundary" do
    test "rejects invalid values and malformed Discovery enrichment" do
      assert_error(
        :invalid_thing_description,
        ThingDescriptions.normalize_and_extract(:invalid, [], :register)
      )

      assert_error(
        :invalid_thing_description,
        ThingDescriptions.from_enriched_map(:invalid, [], :patch)
      )

      assert_error(
        :invalid_thing_description,
        ThingDescriptions.from_enriched_map(%{"registration" => []}, [], :patch)
      )

      thing = Fixtures.thing_description()

      assert_error(
        :invalid_thing_description,
        ThingDescriptions.put_id(thing, "relative identifier", [], :register)
      )
    end
  end

  describe "value validation branches" do
    test "constructors reject malformed values at each public seam" do
      assert_error(:invalid_service, Service.new(:invalid))
      assert_error(:invalid_request, Query.new([], default_limit: 3, max_limit: 2))
      refute Registration.valid?(:invalid)

      assert {:ok, registration} = Registration.create(@now, :absent, :register)
      refute Registration.valid?(%{registration | retrieved: DateTime.add(@now, -1, :second)})

      assert_error(
        :invalid_request,
        Registration.refresh(registration, @now, {:present, %{"expires" => 7}}, :replace)
      )

      assert_error(
        :invalid_request,
        Registration.refresh(registration, @now, {:present, %{7 => "invalid"}}, :replace)
      )
    end
  end

  defp repository(service, state), do: %{service | repository: {StubRepository, state}}

  defp entry do
    {:ok, registration} = Registration.create(@now, :absent, :register)
    thing = Fixtures.thing_description()
    {:ok, entry} = Entry.new("urn:example:thing:1", thing, registration)
    entry
  end

  defp result_code({:error, :conflict}), do: :conflict
  defp result_code(_result), do: :repository_failure

  defp replace_code({:error, :conflict}), do: :conflict
  defp replace_code({:error, :not_found}), do: :not_found
  defp replace_code(_result), do: :repository_failure

  defp delete_code(result), do: replace_code(result)

  defp assert_error(code, result) do
    assert {:error, %Error{code: ^code}} = result
  end
end
