defmodule WotexLabWorkbench.Documentation.StorybookBuilderTest do
  use ExUnit.Case, async: false

  alias WotexLabWorkbench.Documentation.{DesignContract, StorybookBuilder}

  @tag timeout: 120_000
  test "builds and re-adopts the production Phoenix Assets stories below a repository path" do
    source = System.get_env("PHOENIX_ASSETS_CANDIDATE")

    if is_binary(source) and source != "" do
      destination = temporary_path("storybook")
      adopted = temporary_path("adopted")

      on_exit(fn ->
        File.rm_rf(destination)
        File.rm_rf(adopted)
      end)

      assert {:ok, built} =
               StorybookBuilder.run(
                 source: Path.expand(source),
                 destination: destination,
                 base_path: "/wotex/design-system/"
               )

      assert built.manifest["schema_version"] == "wotex-storybook-artifact/v1"
      assert built.manifest["base_path"] == "/wotex/design-system/"
      assert built.manifest["story_count"] >= 40
      assert built.manifest["file_count"] > built.manifest["story_count"]
      assert {:ok, contract} = DesignContract.current()
      assert built.manifest["design_system"] == contract

      iframe = File.read!(Path.join(destination, "iframe.html"))
      assert iframe =~ ~s(src="/wotex/design-system/assets/)
      refute iframe =~ ~r/src="https?:\/\//
      assert File.regular?(Path.join(destination, "storybook-manifest.json"))
      refute Enum.any?(all_files(destination), &String.ends_with?(&1, ".map"))

      assert {:ok, adopted_build} =
               StorybookBuilder.run(
                 artifact: destination,
                 destination: adopted,
                 base_path: "/wotex/design-system/"
               )

      assert adopted_build.manifest == built.manifest

      assert File.read!(Path.join(adopted, "index.html")) ==
               File.read!(Path.join(destination, "index.html"))
    end
  end

  test "rejects ambiguous producers and unsafe bases before creating output" do
    destination = temporary_path("invalid")

    assert {:error, {:invalid_storybook_options, _}} =
             StorybookBuilder.run(destination: destination, base_path: "/design-system/")

    assert {:error, {:invalid_storybook_base_path, _}} =
             StorybookBuilder.run(
               artifact: temporary_path("missing"),
               destination: destination,
               base_path: "../design-system"
             )

    refute File.exists?(destination)
  end

  defp all_files(root) do
    root
    |> File.ls!()
    |> Enum.flat_map(fn name ->
      path = Path.join(root, name)

      if File.dir?(path),
        do: Enum.map(all_files(path), &Path.join(name, &1)),
        else: [name]
    end)
  end

  defp temporary_path(name) do
    Path.join(System.tmp_dir!(), "wotex-#{name}-#{token()}")
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
end
