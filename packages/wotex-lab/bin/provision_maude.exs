# Explicit, digest-verified provisioning of the pinned Maude release for the
# optional formal profile. Runs with Elixir alone:
# `elixir bin/provision_maude.exs [target-dir]` (default `tmp/maude`).
#
# Maude is GPL-2.0 licensed and is not part of this package. This script only
# fetches the exact release archive named below, refuses anything whose SHA-256
# differs, unpacks it locally and prints the path to export as WOTEX_LAB_MAUDE.
# Nothing in the library calls it.

defmodule Wotex.Lab.Check.ProvisionMaude do
  @moduledoc false

  @release "Maude3.5.1"
  @base "https://github.com/maude-lang/Maude/releases/download/"
  @archives %{
    {:unix, :darwin, "aarch64"} =>
      {"Maude-3.5.1-macos-arm64.zip",
       "95851274f57b3853aab833674e2b770ed800f38fb1f3d03c97dcac56346c13dc"},
    {:unix, :darwin, "x86_64"} =>
      {"Maude-3.5.1-macos-x86_64.zip",
       "938eb55fbca44f7f8de71fdb8eeb41f8004ed0a440a3caa37702fee3fc3c79bf"},
    {:unix, :linux, "x86_64"} =>
      {"Maude-3.5.1-linux-x86_64.zip",
       "72ed1ca87e3b3d0dfc6ee1436baf154bf04c45ff97d521bec040c5e8dfc8f92c"}
  }

  @spec run([String.t()]) :: :ok
  def run(argv) do
    target =
      argv
      |> List.first()
      |> Kernel.||("tmp/maude")
      |> Path.expand()

    {family, os} = :os.type()

    arch =
      :erlang.system_info(:system_architecture)
      |> List.to_string()
      |> String.split("-")
      |> hd()

    {file, digest} =
      Map.get(@archives, {family, os, arch}) ||
        abort(
          "no pinned Maude release for #{family}/#{os}/#{arch}; install Maude yourself and set WOTEX_LAB_MAUDE"
        )

    IO.puts(
      "Maude is GPL-2.0 licensed by its authors (https://github.com/maude-lang/Maude); this fetches release #{@release}, archive #{file}, sha256 #{digest}."
    )

    bytes = fetch(@base <> @release <> "/" <> file)
    actual = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    actual == digest ||
      abort("digest mismatch: expected #{digest}, got #{actual}; nothing was unpacked")

    File.mkdir_p!(target)
    {:ok, _} = :zip.extract(bytes, cwd: String.to_charlist(target))
    executable = Path.join(target, "maude")
    File.chmod!(executable, 0o755)
    IO.puts("verified and unpacked: export WOTEX_LAB_MAUDE=#{executable}")
  end

  defp fetch(url) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(
           :get,
           {String.to_charlist(url), []},
           [ssl: ssl, timeout: 120_000, autoredirect: true],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _, body}} -> body
      other -> abort("download failed: #{inspect(other, limit: 10)}")
    end
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.ProvisionMaude.run(System.argv())
