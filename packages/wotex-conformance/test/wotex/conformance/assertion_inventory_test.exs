defmodule Wotex.Conformance.AssertionInventoryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Conformance.TestFixtures

  @standard_identifier "w3c.wot.thing-description"
  @standard_revision "2023-12-05"
  @standard_source "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/"

  test "bundled assertions retain revision-pinned provenance" do
    corpora = [TestFixtures.corpus!(), TestFixtures.thing_model_corpus!()]

    vectors =
      corpora
      |> Enum.flat_map(& &1.vectors)
      |> Enum.sort_by(& &1.id)

    for vector <- vectors do
      claim = vector.claim
      standard = claim.standard

      assert vector.revision == "1.0.0"
      assert claim.revision == "1.0.0"
      assert claim.evidence_profile == "value"
      assert standard["identifier"] == @standard_identifier
      assert standard["revision"] == @standard_revision
      assert standard["source"] == @standard_source
      assert is_binary(standard["section"]) and standard["section"] != ""
      assert claim.assertions != []
      assert claim.assertions == Enum.sort(Enum.uniq(claim.assertions))
      assert vector.provenance["source"] == standard["source"]
      assert vector.provenance["standard_section"] == standard["section"]
    end
  end
end
