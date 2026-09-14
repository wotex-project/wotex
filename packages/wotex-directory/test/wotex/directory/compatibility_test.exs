defmodule Wotex.Directory.CompatibilityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory
  alias Wotex.Directory.{Authorization, Clock, Context, Cursor, Entry, Error, Event, Expiry}

  alias Wotex.Directory.{
    Identifier,
    Introduction,
    Mutation,
    Page,
    Query,
    Registration,
    Repository
  }

  alias Wotex.Directory.Service

  test "the accepted directory facade and required callback arities remain explicit" do
    assert Directory.__info__(:functions) == [
             delete: 3,
             delete: 4,
             expire: 2,
             expire: 3,
             get: 3,
             introduction: 1,
             list: 2,
             list: 3,
             patch: 4,
             patch: 5,
             query: 3,
             register: 3,
             register: 4,
             replace: 4,
             replace: 5
           ]

    for {module, callbacks} <- [
          {Repository, [delete: 4, expire_due: 5, fetch: 3, insert: 3, list: 5, replace: 4]},
          {Authorization, [authorize: 5]},
          {Clock, [now: 1]},
          {Identifier, [generate: 1]}
        ] do
      assert Enum.sort(module.behaviour_info(:callbacks)) == callbacks
      assert module.behaviour_info(:optional_callbacks) == []
    end
  end

  test "the accepted public value fields contain no offset or stream authority" do
    for {module, fields} <- [
          {Context, ~w(authorization principal repository)a},
          {Cursor, ~w(collection_revision last_identifier)a},
          {Entry, ~w(identifier registration state thing_description version)a},
          {Error, ~w(__exception__ code details message path phase)a},
          {Event, ~w(data type)a},
          {Expiry, ~w(cutoff entries strategy)a},
          {Introduction, ~w(media_type path thing_description)a},
          {Mutation, ~w(entry operation status)a},
          {Page, ~w(collection_revision entries next_cursor)a},
          {Query, ~w(cursor format limit profile)a},
          {Registration, ~w(created expires extensions modified retrieved ttl)a},
          {Service,
           ~w(authorization clock default_expiry_batch_limit default_page_limit expiry_strategy identifier introduction max_expiry_batch_limit max_page_limit max_patch_depth max_patch_nodes repository thing_description_options)a}
        ] do
      assert module |> struct() |> Map.from_struct() |> Map.keys() |> Enum.sort() == fields
    end
  end

  test "default bounds and caller-selected time retain the accepted compatibility baseline" do
    defaults = Service.__struct__()
    assert defaults.clock == nil
    assert defaults.repository == nil
    assert defaults.authorization == nil
    assert defaults.identifier == nil
    assert defaults.default_page_limit == 50
    assert defaults.max_page_limit == 200
    assert defaults.default_expiry_batch_limit == 100
    assert defaults.max_expiry_batch_limit == 1_000
    assert defaults.expiry_strategy == :purge
    assert defaults.max_patch_depth == 64
    assert defaults.max_patch_nodes == 100_000
    assert defaults.thing_description_options == []
    assert {:ok, %Query{profile: :listing, limit: 50, format: :array, cursor: nil}} = Query.new()
    assert {:error, %Error{code: :invalid_service}} = Service.new([])
    assert {:error, %Error{code: :invalid_request}} = Query.new(offset: 0)
  end

  test "every accepted error code retains its deterministic message and value shape" do
    messages = [
      invalid_service: "directory service configuration is invalid",
      invalid_context: "directory request context is invalid",
      invalid_request: "directory request is invalid",
      invalid_thing_description: "Thing Description is invalid",
      identifier_mismatch: "Thing Description identifier does not match the target",
      not_found: "directory entry was not found",
      expired: "directory entry is expired",
      forbidden: "directory operation is not authorized",
      conflict: "directory operation conflicts with current state",
      collection_changed: "directory collection changed during pagination",
      unsupported_query_profile: "directory query profile is unsupported",
      invalid_page: "directory repository returned an invalid page",
      authorization_failure: "directory authorization port failed",
      repository_failure: "directory repository port failed",
      clock_failure: "directory clock port failed",
      clock_regression: "directory clock precedes registration history",
      identifier_failure: "directory identifier port failed"
    ]

    for {code, message} <- messages do
      assert Error.message_for(code) == message

      assert Error.new(code, :validation, :register) == %Error{
               code: code,
               phase: :validation,
               message: message,
               path: nil,
               details: %{operation: :register}
             }
    end
  end
end
