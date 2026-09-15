Code.require_file("scenarios.exs", __DIR__)

defmodule Wotex.Matter.SoftwareLane do
  @moduledoc false

  alias Wotex.Matter.{SoftwareCommand, SoftwareScenarios}

  @spec main() :: :ok
  def main do
    suffix =
      case System.fetch_env!("WOTEX_SOFTWARE_SANITIZED") do
        "true" -> "-sanitized"
        "false" -> ""
        _ -> Mix.raise("invalid_software_native_lane")
      end

    for directory <- ["/run/paa", "/run/untrusted-paa"] do
      File.mkdir!(directory)
      File.chmod!(directory, 0o700)
    end

    for name <- ~w(Chip-Test-PAA-FFF1-Cert.der Chip-Test-PAA-NoVID-Cert.der) do
      path = "/run/paa/" <> name
      File.cp!("/artifacts/paa/" <> name, path)
      File.chmod!(path, 0o600)
    end

    untrusted = "Chip-Test-PAA-NoVID-ToResignPAIs-Cert.der"
    File.cp!("/artifacts/paa/" <> untrusted, "/run/untrusted-paa/" <> untrusted)
    File.chmod!("/run/untrusted-paa/" <> untrusted, 0o600)

    artifacts = %{
      host: "/artifacts/bin/wotex-matter-host" <> suffix,
      flow_host: "/artifacts/bin/wotex-matter-flow-host" <> suffix,
      contract_driver: "/artifacts/bin/wotex-matter-contract-driver" <> suffix,
      controller_test: "/artifacts/bin/wotex-matter-controller-test" <> suffix,
      lighting: "/artifacts/bin/chip-lighting-app",
      all_clusters: "/artifacts/bin/chip-all-clusters-app",
      bridge: "/artifacts/bin/chip-bridge-app",
      paa: "/run/paa",
      untrusted_paa: "/run/untrusted-paa"
    }

    SoftwareScenarios.with_fixtures(artifacts, "/run/fixtures", fn fixtures ->
      environment =
        Map.merge(fixtures, %{
          "WOTEX_REQUIRE_SOFTWARE" => "1",
          "WOTEX_SOFTWARE_RESULT_PATH" => "/run/fixtures/acceptance.json",
          "ERL_FLAGS" => System.fetch_env!("ERL_FLAGS"),
          "MIX_HOME" => System.fetch_env!("MIX_HOME"),
          "HEX_HOME" => System.fetch_env!("HEX_HOME"),
          "LANG" => "C.UTF-8",
          "ASAN_OPTIONS" => "detect_leaks=1:halt_on_error=1",
          "UBSAN_OPTIONS" => "halt_on_error=1"
        })

      SoftwareCommand.run!(
        "mix",
        ["test", "--include", "interop", "--include", "software", "--exclude", "hardware"],
        timeout: 2_700_000,
        log: "/run/fixtures/test.log",
        env: Map.to_list(environment)
      )
    end)

    Mix.shell().info("Matter required software cases passed and owned peers were reaped")
    :ok
  end
end

Wotex.Matter.SoftwareLane.main()
