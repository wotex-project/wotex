Code.require_file("../../../bin/support/compatibility_review.exs", __DIR__)

defmodule Wotex.Lab.CompatibilityReviewTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Check.CompatibilityReview

  @digest "sha256:" <> String.duplicate("a", 64)
  @lanes %{
    "minimum" => %{"elixir" => "1.18.4-otp-27", "otp" => "27.3.4.15"},
    "current" => %{"elixir" => "1.20.2-otp-29", "otp" => "29.0.4"}
  }

  test "the review binds the complete API inventory without granting release decisions" do
    assert {:ok, review} = CompatibilityReview.build(api(), @digest, @lanes)
    assert :ok = CompatibilityReview.validate(review)
    assert {:ok, encoded} = CompatibilityReview.encode(review)
    assert {:ok, ^review} = Wotex.JSON.decode(encoded)

    assert review["api_baseline"] == %{
             "path" => "priv/provenance/wotex-lab-api.json",
             "digest" => @digest,
             "schema_version" => "2.0.0",
             "modules" => 1,
             "exports" => 2,
             "typespec_clauses" => 1,
             "structs" => 1,
             "behaviours" => 1,
             "module_documentation" => %{
               "documented" => 1,
               "hidden" => 0,
               "missing" => 0
             },
             "export_documentation" => %{
               "documented" => 1,
               "hidden" => 1,
               "missing" => 0
             },
             "documented_defaults" => 1
           }

    assert Enum.all?(review["decisions"], &(&1["state"] == "maintainer_decision_required"))

    assert Enum.find(review["gates"], &(&1["id"] == "stable_api_candidate"))["state"] ==
             "maintainer_decision_required"
  end

  test "unknown schemas, malformed documentation and incomplete toolchains fail closed" do
    assert {:error, {:unsupported_api_baseline, "3.0.0"}} =
             CompatibilityReview.build(%{api() | "schema_version" => "3.0.0"}, @digest, @lanes)

    [module] = api()["modules"]
    [documented, hidden] = module["functions"]

    invalid =
      put_in(api(), ["modules"], [%{module | "functions" => [documented, documented, hidden]}])

    assert {:error, :invalid_api_baseline} = CompatibilityReview.build(invalid, @digest, @lanes)

    invalid = put_in(api(), ["modules", Access.at(0), "documentation"], %{"status" => "unknown"})
    assert {:error, :invalid_api_baseline} = CompatibilityReview.build(invalid, @digest, @lanes)

    assert {:error, :invalid_compatibility_review_input} =
             CompatibilityReview.build(api(), "sha256:no", @lanes)

    assert {:error, :invalid_toolchains} =
             CompatibilityReview.build(api(), @digest, Map.delete(@lanes, "minimum"))
  end

  test "review validation rejects unknown fields and stronger decision claims" do
    {:ok, review} = CompatibilityReview.build(api(), @digest, @lanes)

    assert {:error, :invalid_compatibility_review} =
             CompatibilityReview.validate(Map.put(review, "unknown", true))

    decisions =
      Enum.map(review["decisions"], fn decision ->
        if decision["id"] == "stable_api", do: %{decision | "state" => "approved"}, else: decision
      end)

    assert {:error, :invalid_compatibility_review} =
             CompatibilityReview.validate(%{review | "decisions" => decisions})
  end

  defp api do
    %{
      "schema_version" => "2.0.0",
      "package" => "wotex_lab",
      "version" => "0.1.0",
      "compatibility_status" => "pre-1.0-review-baseline",
      "modules" => [
        %{
          "module" => "Elixir.Wotex.Lab",
          "behaviours" => ["Elixir.Wotex.Lab.Contract"],
          "struct_keys" => ["id"],
          "documentation" => %{"status" => "documented", "sha256" => @digest},
          "functions" => [
            %{
              "name" => "new",
              "arity" => 1,
              "documentation" => %{
                "status" => "documented",
                "sha256" => @digest,
                "signatures" => ["new(opts \\ [])"],
                "defaults" => 1
              }
            },
            %{
              "name" => "__struct__",
              "arity" => 0,
              "documentation" => %{"status" => "hidden", "signatures" => ["%Wotex.Lab{}"]}
            }
          ],
          "specs" => [%{"name" => "new", "arity" => 1, "contract" => "new(keyword()) :: map()"}]
        }
      ]
    }
  end
end
