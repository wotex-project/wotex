defmodule Wotex.Directory.ValueContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory.{Clock, Context, Cursor, Entry, Error, Fixtures, Identifier}
  alias Wotex.Directory.{Introduction, Page, Query, Registration}

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

      for arguments <- [[nil], [:principal, :not_options], [:principal, [unknown: true]]] do
        error = assert_raise Error, fn -> apply(Context, :new!, arguments) end
        assert error.code == :invalid_context and error.phase == :validation
      end

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
      assert {:ok, query} = Query.new([], default_limit: 3, max_limit: 5)
      assert query == %Query{profile: :listing, limit: 3, format: :array}

      {:ok, cursor} = Cursor.encode("r1", "urn:example:a")

      assert {:ok, %Query{cursor: ^cursor, format: :collection}} =
               Query.new(
                 [cursor: cursor, format: :collection],
                 default_limit: 3,
                 max_limit: 5
               )

      for options <- [
            [limit: 0],
            [limit: 6],
            [format: :unknown],
            [cursor: ""],
            [cursor: "wtd1.only-two"],
            [cursor: :not_a_cursor],
            [unknown: true]
          ] do
        assert {:error, %Error{code: :invalid_request, phase: :listing}} =
                 Query.new(options, default_limit: 3, max_limit: 5)
      end

      assert {:error, %Error{code: :unsupported_query_profile}} =
               Query.new([profile: :jsonpath], default_limit: 3, max_limit: 5)

      assert {:error, %Error{code: :invalid_request}} = Query.new(:invalid, [])
      assert {:error, %Error{code: :invalid_request}} = Query.new([], [:not_a_pair])
      assert {:error, %Error{code: :invalid_request}} = Query.new([], unknown: 1)
      assert {:error, %Error{code: :invalid_request}} = Query.validate(:invalid, 5)
    end

    test "encodes and decodes opaque keyset cursors" do
      assert {:ok, cursor} = Cursor.encode("revision 1", "urn:example:a")
      assert is_binary(cursor)
      refute String.contains?(cursor, "urn:example:a")

      assert {:ok, %Cursor{collection_revision: "revision 1", last_identifier: "urn:example:a"}} =
               Cursor.decode(cursor)

      assert Cursor.valid?(cursor)

      for invalid <- ["", "wtd1", "wtd0.cmV2.dXJuOmE", "wtd1.@@.@@", :not_a_string] do
        assert {:error, %Error{code: :invalid_request, phase: :listing}} = Cursor.decode(invalid)
        refute Cursor.valid?(invalid)
      end

      assert {:error, %Error{code: :invalid_request}} = Cursor.encode("", "urn:example:a")
      assert {:error, %Error{code: :invalid_request}} = Cursor.encode("r1", "relative")
    end

    test "validates ordered active pages and produces the next query" do
      first = entry("urn:example:a")
      second = entry("urn:example:b")
      query = %Query{profile: :listing, limit: 2, format: :collection}

      assert {:ok, page} =
               Page.new(entries: [first, second], collection_revision: "r1", more?: true)

      assert Page.validate(page, query, @now) == :ok
      assert {:ok, %Cursor{last_identifier: "urn:example:b"}} = Cursor.decode(page.next_cursor)

      next_query = Page.next_query(page, query)
      assert next_query == %Query{query | cursor: page.next_cursor}

      third = entry("urn:example:c")
      {:ok, continuation} = Page.new(entries: [third], collection_revision: "r1")
      assert Page.validate(continuation, next_query, @now) == :ok

      assert {:ok, last} =
               Page.new(entries: [first, second], collection_revision: "r1", more?: false)

      assert last.next_cursor == nil
      assert Page.next_query(last, query) == nil
    end

    test "rejects malformed, inconsistent, stale, unordered, and inactive pages" do
      first = entry("urn:example:a")
      second = entry("urn:example:b")
      query = %Query{profile: :listing, limit: 2, format: :array}

      assert {:error, %Error{code: :invalid_page}} = Page.new(:not_options)
      assert {:error, %Error{code: :invalid_page}} = Page.new([:not_a_pair])
      assert {:error, %Error{code: :invalid_page}} = Page.new(unknown: true)

      assert {:error, %Error{code: :invalid_page}} =
               Page.new(entries: [], collection_revision: "")

      assert {:error, %Error{code: :invalid_page}} =
               Page.new(entries: [], collection_revision: "r1", more?: true)

      assert {:error, %Error{code: :invalid_page}} =
               Page.new(entries: [first], collection_revision: "r1", more?: :maybe)

      assert_raise Error, fn -> Page.new!(entries: :not_entries, collection_revision: "r1") end

      base = %Page{entries: [first, second], collection_revision: "r1"}

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | entries: [first, second, first]}, query, @now)

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | entries: [second, first]}, query, @now)

      expired = %{first | state: :expired}

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | entries: [expired]}, query, @now)

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | next_cursor: "not-a-cursor"}, query, @now)

      {:ok, wrong_cursor} = Cursor.encode("r1", "urn:example:a")

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | next_cursor: wrong_cursor}, query, @now)

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | entries: [nil]}, query, @now)

      malformed_registration = %{first.registration | expires: "not-a-time"}
      malformed_entry = %{first | registration: malformed_registration}

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(%{base | entries: [malformed_entry]}, query, @now)

      {:ok, stale} = Cursor.encode("older", "urn:example:a")

      assert {:error, %Error{code: :collection_changed}} =
               Page.validate(base, %{query | cursor: stale}, @now)

      {:ok, overlapping} = Cursor.encode("r1", "urn:example:b")

      assert {:error, %Error{code: :invalid_page}} =
               Page.validate(base, %{query | cursor: overlapping}, @now)

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
