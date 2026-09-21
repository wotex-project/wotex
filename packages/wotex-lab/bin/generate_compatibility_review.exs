# Deterministic release-readiness inputs. The generated record inventories the
# exact API baseline and repository toolchain cohort but deliberately cannot
# grant publication, release-candidate or stable-API decisions.

Code.require_file("support/compatibility_review.exs", __DIR__)

defmodule Wotex.Lab.Check.GenerateCompatibilityReview do
  @moduledoc false

  alias Wotex.Lab.Check.CompatibilityReview

  @spec run([String.t()]) :: :ok
  def run(arguments) do
    root = Path.expand("..", __DIR__)
    repository = Path.expand("../..", root)
    api_path = Path.join(root, "priv/provenance/wotex-lab-api.json")
    output = Path.join(root, "priv/provenance/wotex-lab-compatibility.json")

    with {:ok, api_bytes} <- File.read(api_path),
         {:ok, api} <- Wotex.JSON.decode(api_bytes),
         {:ok, packages} <-
           YamlElixir.read_from_file(Path.join(repository, "tooling/packages.yaml")),
         {:ok, review} <- CompatibilityReview.build(api, digest(api_bytes), packages["lanes"]),
         {:ok, encoded} <- CompatibilityReview.encode(review) do
      bytes = encoded <> "\n"

      case arguments do
        ["--check"] ->
          File.read(output) == {:ok, bytes} ||
            abort("compatibility review is stale; run with --write")

          IO.puts(
            "compatibility review: API baseline, toolchains, source gates and maintainer decisions match"
          )

        ["--write"] ->
          File.write!(output, bytes)
          IO.puts("compatibility review: wrote #{output}")

        _ ->
          abort("usage: mix run --no-start bin/generate_compatibility_review.exs --check|--write")
      end
    else
      {:error, reason} -> abort("compatibility review failed: #{inspect(reason)}")
    end
  end

  defp digest(bytes),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.GenerateCompatibilityReview.run(System.argv())
