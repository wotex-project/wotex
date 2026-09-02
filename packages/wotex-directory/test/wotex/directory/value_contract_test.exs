defmodule Wotex.Directory.ValueContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory.{Clock, Context, Entry, Error, Fixtures, Identifier, Introduction}
  alias Wotex.Directory.{Page, Query, Registration}

  @now ~U[2026-09-02 10:00:00Z]

  describe "identifier, context, and Introduction values" do
    test "accepts absolute IRIs and rejects relative, blank, control, and non-string values" do
      assert Identifier.valid?("urn:example:thing:1")
      assert Identifier.valid?("https://example.test/things/å")
      refute Identifier.valid?("relative")
      refute Identifier.valid?("")
      refute Identifier.valid?("https://example.test/with space")
      refute Identifier.valid?("1invalid:scheme")
      refute Identifier.valid?(:not_a_string)
    end

    test "raising context constructor reuses the typed error" do
      assert %Context{principal: :principal} = Context.new!(:principal)
      assert_raise Error, fn -> Context.new!(nil) end
      assert {:error, %Error{code: :invalid_context}} = Context.new(:principal, :not_options)
      refute Context.valid?(:not_a_context)
    end

    test "Introduction requires a validated Thing Description with an absolute identifier" do
      assert {:ok, introduction} =
               Fixtures.thing_description("urn:example:directory") |> Introduction.new()

      assert introduction.path == "/.well-known/wot"

      {:ok, invalid} =
        Wotex.ThingDescription.from_map(%{"id" => "relative"}, validate: false)

      assert {:error, %Error{code: :invalid_service}} = Introduction.new(invalid)
      assert {:error, %Error{code: :invalid_service}} = Introduction.new(%{})
    end

    test "system clock returns a UTC DateTime without state" do
      assert {:ok, %DateTime{time_zone: "Etc/UTC"}} = Clock.System.now(:unused)
    end
  end

  describe "entry values" do
    test "validates identifier equality, versions, registration type, and state" do
      thing_description = Fixtures.thing_description("urn:example:thing:1")
      registration = registration()

      assert {:ok, entry} = Entry.new("urn:example:thing:1", thing_description, registration)
      assert Entry.active?(entry, @now)
      assert Entry.valid?(entry)
      refute Entry.valid?(:not_an_entry)

      assert {:error, %Error{code: :invalid_request}} =
               Entry.new("urn:example:other", thing_description, registration)

      assert {:error, %Error{code: :invalid_request}} =
               Entry.new("urn:example:thing:1", thing_description, registration, version: 0)

      assert {:error, %Error{code: :invalid_request}} =
               Entry.new("urn:example:thing:1", thing_description, registration, state: :unknown)

      assert {:error, %Error{code: :invalid_request}} =
               Entry.new("urn:example:thing:1", thing_description, :not_registration)

      assert {:error, %Error{code: :invalid_request}} =
               Entry.new("urn:example:thing:1", thing_description, registration, :not_options)

      assert {:error, %Error{code: :invalid_request}} =
               Entry.new("urn:example:thing:1", thing_description, registration, [:not_a_pair])

      assert {:error, %Error{code: :invalid_request}} =
               Entry.new("urn:example:thing:1", thing_description, registration, unknown: true)

      malformed_registration = %{registration | created: :not_a_datetime}
      refute Entry.valid?(%{entry | registration: malformed_registration})
    end

    test "expired state is inactive independently of absolute expiry" do
      {:ok, entry} =
        Entry.new(
          "urn:example:thing:1",
          Fixtures.thing_description("urn:example:thing:1"),
          registration(),
          state: :expired
        )

      refute Entry.active?(entry, @now)
    end
  end

  describe "query and page values" do
    test "constructs defaults and validates every public query bound" do
      assert {:ok, query} = Query.new([], default_limit: 3, maximum_limit: 5)
      assert query == %Query{profile: :listing, offset: 0, limit: 3, format: :array}

      assert {:ok, %Query{collection_revision: "r1", format: :collection}} =
               Query.new(
                 [collection_revision: "r1", format: :collection],
                 default_limit: 3,
                 maximum_limit: 5
               )

      for options <- [
            [offset: -1],
            [limit: 0],
            [limit: 6],
            [format: :unknown],
            [collection_revision: ""],
            [unknown: true]
          ] do
        assert {:error, %Error{code: :invalid_request}} =
                 Query.new(options, default_limit: 3, maximum_limit: 5)
      end

      assert {:error, %Error{code: :unsupported_query_profile}} =
               Query.new([profile: :jsonpath], default_limit: 3, maximum_limit: 5)

      assert {:error, %Error{code: :invalid_request}} = Query.new(:invalid, [])
      assert {:error, %Error{code: :invalid_request}} = Query.new([], [:not_a_pair])
      assert {:error, %Error{code: :invalid_request}} = Query.new([], unknown: 1)
      assert {:error, %Error{code: :invalid_request}} = Query.validate(:invalid, 5)
    end

    test "validates ordered active pages and produces the next query" do
      first = entry("urn:example:a")
      second = entry("urn:example:b")
      query = %Query{profile: :listing, offset: 0, limit: 2, format: :collection}

      page =
        Page.new!(
          entries: [first, second],
          offset: 0,
          limit: 2,
          next_offset: 2,
          collection_revision: "r1"
        )

      assert Page.validate(page, query, @now) == :ok

      assert Page.next_query(page, query) == %Query{
               profile: :listing,
               offset: 2,
               limit: 2,
               format: :collection,
               collection_revision: "r1"
             }

      last = %{page | next_offset: nil}
      assert Page.next_query(last, query) == nil
    end

    test "rejects malformed, inconsistent, stale, unordered, and inactive pages" do
      first = entry("urn:example:a")
      second = entry("urn:example:b")
      query = %Query{profile: :listing, offset: 0, limit: 2, format: :array}

      assert {:error, %Error{code: :invalid_page}} = Page.new(:not_options)
      assert {:error, %Error{code: :invalid_page}} = Page.new([:not_a_pair])
      assert {:error, %Error{code: :invalid_page}} = Page.new(unknown: true)
      assert_raise Error, fn -> Page.new!(entries: :not_entries) end

      base = %Page{
        entries: [first, second],
        offset: 0,
        limit: 2,
        collection_revision: "r1"
      }

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | offset: 1}, query, @now)

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | entries: [first, second, first]}, query, @now)

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | entries: [second, first]}, query, @now)

      expired = %{first | state: :expired}

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | entries: [expired]}, query, @now)

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | next_offset: 3}, query, @now)

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | entries: [nil]}, query, @now)

      malformed_registration = %{first.registration | expires: "not-a-time"}
      malformed_entry = %{first | registration: malformed_registration}

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | entries: [malformed_entry]}, query, @now)

      stale_query = %{query | collection_revision: "older"}

      assert {:error, %Error{code: :collection_changed}} =
               Page.validate(base, stale_query, @now)

      assert {:error, %Error{code: :invalid_page}} = Page.validate(:invalid, query, @now)
    end
  end

  defp entry(identifier) do
    {:ok, entry} = Entry.new(identifier, Fixtures.thing_description(identifier), registration())
    entry
  end

  defp registration do
    {:ok, registration} = Registration.create(@now, :absent, :register)
    registration
  end
end
