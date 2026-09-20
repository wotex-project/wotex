defmodule WotexLabWorkbench.Documentation.PublicationTest do
  use ExUnit.Case, async: false

  alias WotexLabWorkbench.Documentation.Publication

  test "combines separately manifested trees at root and repository subpaths" do
    for {base_path, storybook_base} <- [
          {"/docs/", "/design-system/"},
          {"/wotex/docs/", "/wotex/design-system/"}
        ] do
      root = temporary_path("publication-fixture")
      docs = Path.join(root, "docs")
      storybook = Path.join(root, "storybook")
      destination = Path.join(root, "public")
      File.mkdir_p!(destination)
      File.write!(Path.join(destination, "preceding-publication"), "complete")
      fixture_docs(docs, base_path)
      fixture_storybook(storybook, storybook_base)
      on_exit(fn -> File.rm_rf(root) end)

      assert {:ok, published} =
               Publication.publish(
                 %{documentation: docs, storybook: storybook},
                 destination: destination,
                 base_path: base_path
               )

      storybook_relative = String.trim(storybook_base, "/")
      docs_relative = String.trim(base_path, "/")

      assert File.regular?(Path.join([destination, docs_relative, "start", "index.html"]))
      assert File.regular?(Path.join([destination, storybook_relative, "index.html"]))
      assert File.regular?(Path.join(destination, "publication-manifest.json"))
      refute File.exists?(Path.join(destination, "preceding-publication"))
      assert published.manifest["documentation_base_path"] == base_path
      assert published.manifest["storybook_base_path"] == storybook_base
      assert published.manifest["output_digest"] =~ ~r/\Asha256:[0-9a-f]{64}\z/
    end
  end

  test "a failed documentation or Storybook preflight retains the preceding publication" do
    root = temporary_path("publication-rollback")
    docs = Path.join(root, "docs")
    storybook = Path.join(root, "storybook")
    destination = Path.join(root, "public")
    File.mkdir_p!(destination)
    File.write!(Path.join(destination, "preceding-publication"), "complete")
    fixture_docs(docs, "/wotex/docs/")
    fixture_storybook(storybook, "/wotex/design-system/")
    File.mkdir_p!(Path.join(docs, "wotex/design-system"))
    File.write!(Path.join(docs, "wotex/design-system/index.html"), "collision")
    on_exit(fn -> File.rm_rf(root) end)

    assert {:error, {:documentation_storybook_collision, ["wotex/design-system/index.html"]}} =
             Publication.publish(
               %{documentation: docs, storybook: storybook},
               destination: destination,
               base_path: "/wotex/docs/"
             )

    assert File.read!(Path.join(destination, "preceding-publication")) == "complete"
    refute File.exists?(Path.join(destination, "publication-manifest.json"))

    File.write!(Path.join(docs, "site-manifest.json"), "not-json")

    assert {:error, {:invalid_publication_manifest, "site-manifest.json", _}} =
             Publication.publish(
               %{documentation: docs, storybook: storybook},
               destination: destination,
               base_path: "/wotex/docs/"
             )

    assert File.read!(Path.join(destination, "preceding-publication")) == "complete"
  end

  defp fixture_docs(root, base_path) do
    File.mkdir_p!(Path.join([root, String.trim(base_path, "/"), "start"]))
    File.write!(Path.join([root, String.trim(base_path, "/"), "start", "index.html"]), "docs")

    File.write!(
      Path.join(root, "site-manifest.json"),
      JSON.encode!(%{
        "base_path" => base_path,
        "cohort_digest" => "sha256:" <> String.duplicate("a", 64)
      })
    )
  end

  defp fixture_storybook(root, base_path) do
    File.mkdir_p!(root)
    File.write!(Path.join(root, "index.html"), "storybook")

    File.write!(
      Path.join(root, "storybook-manifest.json"),
      JSON.encode!(%{
        "schema_version" => "wotex-storybook-artifact/v1",
        "base_path" => base_path,
        "design_system" => %{"token_digest" => "sha256:" <> String.duplicate("b", 64)}
      })
    )
  end

  defp temporary_path(name) do
    Path.join(System.tmp_dir!(), "wotex-#{name}-#{token()}")
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
end
