defmodule Wotex.Directory.CompatibilityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory.{Authorization, Clock, Error, Identifier, Query, Repository}

  test "required consumer port callback shapes remain explicit" do
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

  test "listing defaults and the absence of offset retain the accepted query behavior" do
    assert {:ok, %Query{profile: :listing, limit: 50, format: :array, cursor: nil}} = Query.new()
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
