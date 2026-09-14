defmodule Wotex.Binding.MQTT.Check.ReleaseCandidate do
  @moduledoc false

  @tool_versions "erlang 27.3.4.15\nelixir 1.18.4-otp-27\n"
  @core_revision "58409779ae9515df2bf120a5f13813cffcb1c59c"
  @runtime_revision "70f9511b8b691665b0c87d84f743891c70c93b9e"

  @package_files ~w(
    .formatter.exs
    CHANGELOG.md
    CODE_OF_CONDUCT.md
    CONTRIBUTING.md
    GOVERNANCE.md
    LICENSE
    NOTICE
    README.md
    SECURITY.md
    docs/plans
    docs/provenance
    docs/reference-consumer-inventory.md
    docs/release-candidate-inventory.md
    docs/runtime-baseline.md
    docs/specs
    lib
    mix.exs
  )

  @excluded_package_files ~w(
    .check.exs
    .claude
    .credo.exs
    .doctor.exs
    .git
    .github
    .tool-versions
    AGENTS.md
    CLAUDE.md
    bin
    config
    cover
    deps
    doc
    docs/tasks
    mix.lock
    priv
    test
  )

  @required_tools ~w(
    deps_get
    compiler
    unused_deps
    formatter
    mix_audit
    credo
    doctor
    ex_doc
    dialyzer
    coverage
    hex_audit
    boundary
    application
    archive
    release_candidate
    diff
  )a

  @spec main() :: :ok
  def main do
    result =
      try do
        verify!()
      catch
        :throw, {:violation, message} -> {:violation, message}
      end

    report(result)
  end

  defp verify! do
    verify_project!()
    verify_legal_and_security!()
    verify_catalogue!()
    verify_documentation!()
    verify_lock!()
    verify_toolchain!()
    verify_gate!()
    :ok
  end

  defp verify_project! do
    project = Mix.Project.config()
    package = Keyword.fetch!(project, :package)

    exact!(Keyword.get(project, :app), :wotex_binding_mqtt, "application name")
    exact!(Keyword.get(project, :version), "0.1.0", "package version")
    exact!(Keyword.get(project, :elixir), "~> 1.18", "Elixir requirement")

    exact!(
      Keyword.get(project, :description),
      "Immutable MQTT command mapping and caller-owned transport adaptation for W3C Web of Things",
      "description"
    )

    exact!(
      Keyword.get(project, :source_url),
      "https://github.com/wotex-project/wotex-binding-mqtt",
      "source URL"
    )

    exact!(Keyword.get(project, :homepage_url), "https://wotex.io", "homepage URL")
    exact!(Keyword.get(package, :name), "wotex_binding_mqtt", "Hex package name")
    exact!(Keyword.get(package, :licenses), ["Apache-2.0"], "package license")

    case Keyword.get(package, :maintainers) do
      [_ | _] -> :ok
      _ -> violation("package maintainers are missing")
    end

    links = Keyword.get(package, :links, %{})

    for {label, value} <- %{
          "Documentation" => "https://hexdocs.pm/wotex_binding_mqtt",
          "Project" => "https://wotex.io",
          "Source" => "https://github.com/wotex-project/wotex-binding-mqtt",
          "W3C WoT MQTT Binding" =>
            "https://w3c.github.io/wot-binding-templates/bindings/protocols/mqtt/"
        } do
      exact!(Map.get(links, label), value, "package link #{label}")
    end

    files = Keyword.get(package, :files, [])
    Enum.each(@package_files, &listed!(files, &1, "package allowlist"))

    Enum.each(@excluded_package_files, fn file ->
      if file in files, do: violation("package allowlist includes private or QA path #{file}")
    end)

    docs = Keyword.get(project, :docs, [])
    extras = docs |> Keyword.get(:extras, []) |> Keyword.keys() |> Enum.map(&to_string/1)

    for extra <- [
          "README.md",
          "LICENSE",
          "NOTICE",
          "docs/reference-consumer-inventory.md",
          "docs/release-candidate-inventory.md",
          "docs/runtime-baseline.md",
          "docs/plans/wotex-binding-mqtt-completion.md"
        ] do
      listed!(extras, extra, "generated documentation")
    end
  end

  defp verify_legal_and_security! do
    license = File.read!("LICENSE")
    notice = File.read!("NOTICE")
    security = File.read!("SECURITY.md")

    require!(license, "Apache License", "LICENSE does not identify Apache License 2.0")
    require!(license, "Copyright 2026 Wotex contributors", "LICENSE copyright is missing")
    require!(notice, "Wotex MQTT Binding", "NOTICE package identity is missing")
    require!(notice, "Copyright 2026 Wotex contributors", "NOTICE copyright is missing")
    require!(security, "security@wotex.io", "private security contact is missing")
    require!(security, "Do not include live", "security handling guidance is missing")
    require!(security, "mix hex.audit", "dependency-audit policy is missing")
  end

  defp verify_catalogue! do
    catalogue = File.read!("docs/specs/catalogue.yaml")

    for path <- quoted_values(catalogue, "path"), do: regular!(path, "catalogued specification")

    catalogue
    |> quoted_evidence_values()
    |> Enum.each(&regular!(&1, "catalogued executable evidence"))
  end

  defp verify_documentation! do
    files = ["README.md", "SECURITY.md" | Path.wildcard("docs/**/*.md")]
    Enum.each(files, &verify_links!/1)
    corpus = Enum.map_join(files, "\n", &File.read!/1)
    readme = File.read!("README.md")
    provenance = File.read!("docs/provenance/mqtt-binding-draft-2026-07-01.md")

    require!(readme, "no published", "release nonclaim is missing")
    require!(readme, "W3C certification is implied", "certification nonclaim is missing")

    require!(provenance, "does not claim W3C conformance", "conformance nonclaim is missing")

    for forbidden <- ["W3C-certified", "W3C certified", "fully WoT conformant"] do
      if String.contains?(corpus, forbidden) do
        violation("documentation contains unsupported claim #{inspect(forbidden)}")
      end
    end
  end

  defp verify_links!(file) do
    source = File.read!(file)

    ~r/\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/
    |> Regex.scan(source, capture: :all_but_first)
    |> List.flatten()
    |> Enum.each(&verify_link!(file, &1))
  end

  defp verify_link!(file, destination) do
    if external_or_anchor?(destination) do
      :ok
    else
      path =
        destination
        |> String.trim_leading("<")
        |> String.trim_trailing(">")
        |> String.split("#", parts: 2)
        |> hd()
        |> then(&Path.expand(&1, Path.dirname(file)))

      unless File.exists?(path) do
        violation("#{file} links to missing local target #{destination}")
      end
    end
  end

  defp external_or_anchor?(destination) do
    destination == "" or String.starts_with?(destination, ["#", "http://", "https://", "mailto:"])
  end

  defp verify_lock! do
    lock = Mix.Dep.Lock.read()
    if map_size(lock) == 0, do: violation("mix.lock is empty")

    Enum.each(lock, fn
      {_, {:hex, _, _, _, _, _, "hexpm", _}} -> :ok
      {name, value} -> violation("locked dependency #{name} is not exact Hex: #{inspect(value)}")
    end)

    if Map.has_key?(lock, :wotex) or Map.has_key?(lock, :wotex_runtime) do
      violation("path-selected sibling dependencies must not create mutable lock entries")
    end
  end

  defp verify_toolchain! do
    exact!(File.read!(".tool-versions"), @tool_versions, "pinned toolchain")
    workflow = File.read!(".github/workflows/ci.yml")

    require!(workflow, @core_revision, "CI does not pin the exact core revision")
    require!(workflow, @runtime_revision, "CI does not pin the exact Runtime revision")
    require!(workflow, "elixir-version: \"1.18.4-otp-27\"", "CI Elixir is not exact")
    require!(workflow, "otp-version: \"27.3.4.15\"", "CI OTP is not exact")
    require!(workflow, "mix deps.get --check-locked", "CI lock bootstrap is incomplete")
    require!(workflow, "mix check --no-retry", "CI does not run the authoritative gate")

    if String.contains?(workflow, "MIX_ENV:") do
      violation("CI must not replace the default gate environment")
    end

    baseline = File.read!("docs/runtime-baseline.md")
    require!(baseline, @core_revision, "public baseline does not pin core")
    require!(baseline, @runtime_revision, "public baseline does not pin Runtime")
  end

  defp verify_gate! do
    {configuration, _} = Code.eval_file(".check.exs")
    tools = configuration |> Keyword.fetch!(:tools) |> Keyword.keys()

    exact!(Keyword.get(configuration, :parallel), false, "gate parallelism")
    exact!(Keyword.get(configuration, :skipped), false, "gate skipped setting")
    Enum.each(@required_tools, &listed!(tools, &1, "default gate"))
    exact!(Keyword.get(configuration[:tools], :ex_unit), false, "duplicate ExUnit tool")
  end

  defp quoted_values(source, key) do
    Regex.scan(~r/^\s*#{Regex.escape(key)}:\s*"([^"]+)"/m, source, capture: :all_but_first)
    |> List.flatten()
  end

  defp quoted_evidence_values(source) do
    values =
      ~r/"(test\/[^\"]+)"/
      |> Regex.scan(source, capture: :all_but_first)
      |> List.flatten()

    if values == [], do: violation("catalogue is missing executable evidence")
    Enum.uniq(values)
  end

  defp regular!(path, label) do
    unless File.regular?(path), do: violation("#{label} is missing: #{path}")
  end

  defp listed!(values, value, label) do
    unless value in values, do: violation("#{label} is missing #{value}")
  end

  defp exact!(actual, expected, label) do
    unless actual == expected do
      violation("#{label} is #{inspect(actual)}; expected #{inspect(expected)}")
    end
  end

  defp require!(source, value, message) do
    unless String.contains?(source, value), do: violation(message)
  end

  defp digest(path) do
    :sha256
    |> :crypto.hash(File.read!(path))
    |> Base.encode16(case: :lower)
  end

  defp violation(message), do: throw({:violation, message})

  defp report(:ok) do
    IO.puts("release-candidate vectors: WBM-P01..WBM-P08")
    IO.puts("locked dependency graph: sha256=#{digest("mix.lock")}")
    IO.puts("declared verification toolchain: Elixir 1.18.4-otp-27 / OTP 27.3.4.15")
    IO.puts("package publication and registry availability: not claimed")
    :ok
  end

  defp report({:violation, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Binding.MQTT.Check.ReleaseCandidate.main()
