defmodule WotexContinuum.ReleaseContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @standard_registered_values [
    WotexContinuum.ActionIntent,
    WotexContinuum.ActionResult,
    WotexContinuum.Capability,
    WotexContinuum.Degradation,
    WotexContinuum.Delivery,
    WotexContinuum.EvidenceReference,
    WotexContinuum.ExecutionScope,
    WotexContinuum.ExitReceipt,
    WotexContinuum.ObservationProposal
  ]

  @nested_values [
    WotexContinuum.Artifact,
    WotexContinuum.CapabilityRequirement,
    WotexContinuum.Failure
  ]

  test "package and wire identities remain independent and package metadata is exact" do
    project = Mix.Project.config()
    package = Keyword.fetch!(project, :package)

    assert project[:app] == :wotex_continuum
    assert project[:version] == "0.1.0"
    assert project[:elixir] == "~> 1.18"
    assert project[:name] == "Wotex Continuum"
    assert project[:source_url] == "https://github.com/wotex-project/wotex-continuum"
    assert project[:homepage_url] == "https://wotex.io"
    assert WotexContinuum.schema_version() == "2.0.0"

    assert package[:name] == "wotex_continuum"
    assert package[:licenses] == ["Apache-2.0"]
    assert package[:maintainers] == ["Tobias Bohwalli <hi@futhr.io>"]

    assert package[:links] == %{
             "Documentation" => "https://hexdocs.pm/wotex_continuum",
             "GitHub" => "https://github.com/wotex-project/wotex-continuum",
             "Project" => "https://wotex.io",
             "W3C Web of Things" => "https://www.w3.org/WoT/"
           }

    assert package[:files] ==
             ~w(docs/THREAT_MODEL.md docs/plans docs/specs lib priv/schemas provenance specs test/vectors .formatter.exs mix.exs README.md LICENSE NOTICE CHANGELOG.md SECURITY.md GOVERNANCE.md CONTRIBUTING.md CODE_OF_CONDUCT.md)
  end

  test "the reviewed supported API export inventory is exact" do
    assert exports(WotexContinuum) ==
             exports(from_map: 1, kinds: 0, module_for_kind: 1, schema_version: 0, to_map: 1)

    assert exports(WotexContinuum.Codec) ==
             exports(canonicalize: 1, decode: 1, decode: 2, encode: 1, encode: 2)

    assert exports(WotexContinuum.CanonicalJSON) == exports(encode: 1)
    assert exports(WotexContinuum.Schema) == exports(fetch: 1, ids: 0, info: 1)
    assert exports(WotexContinuum.ThingReference) == exports(validate: 2)
    assert exports(WotexContinuum.Value) == []

    for module <- @standard_registered_values do
      expected = [__struct__: 0, __struct__: 1, from_map: 1, kind: 0, new: 1, to_map: 1]
      assert exports(module) == exports(expected), inspect(module)
    end

    for module <- @nested_values do
      expected = [__struct__: 0, __struct__: 1, from_map: 1, new: 1, to_map: 1]
      assert exports(module) == exports(expected), inspect(module)
    end

    assert exports(WotexContinuum.Manifest) ==
             exports(
               __struct__: 0,
               __struct__: 1,
               compatible_with?: 3,
               from_map: 1,
               kind: 0,
               new: 1,
               to_map: 1
             )

    assert exports(WotexContinuum.Compatibility) ==
             exports(
               __struct__: 0,
               __struct__: 1,
               evaluate: 3,
               from_map: 1,
               kind: 0,
               new: 1,
               to_map: 1
             )

    assert exports(WotexContinuum.Mode) ==
             exports(
               __struct__: 0,
               __struct__: 1,
               connectivity_states: 0,
               deployments: 0,
               from_map: 1,
               kind: 0,
               new: 1,
               to_map: 1
             )

    assert exports(WotexContinuum.Lifecycle) ==
             exports(
               __struct__: 0,
               __struct__: 1,
               from_map: 1,
               kind: 0,
               new: 1,
               states: 0,
               to_map: 1,
               transition: 3,
               transition: 4
             )
  end

  test "the documented error and limits utility exports are exact" do
    assert exports(WotexContinuum.Error) ==
             exports(
               __struct__: 0,
               __struct__: 1,
               child: 2,
               error: 4,
               error: 5,
               exception: 1,
               from_core: 1,
               message: 1,
               new: 3,
               new: 4,
               new: 5,
               prefix: 2,
               prepend: 2,
               root: 0
             )

    assert exports(WotexContinuum.Limits) ==
             exports(
               __struct__: 0,
               __struct__: 1,
               defaults: 0,
               max_depth: 0,
               new: 1,
               to_options: 1
             )
  end

  test "implementation helper exports remain explicitly inventoried" do
    assert exports(WotexContinuum.Contract) ==
             exports(base: 1, envelope: 2, exact: 4, normalize: 3)

    assert exports(WotexContinuum.Validation) ==
             exports(
               boolean: 2,
               compare_timestamps: 2,
               digest: 2,
               enum: 3,
               enum_list: 3,
               enum_list: 4,
               extensions: 2,
               iri: 2,
               json_value: 2,
               list: 2,
               map_list: 3,
               nested: 3,
               non_negative_integer: 2,
               normalize: 2,
               optional_string: 3,
               options: 2,
               positive_integer: 2,
               required: 2,
               semver: 2,
               string: 2,
               string: 3,
               string_list: 2,
               string_list: 3,
               struct_input: 1,
               struct_input: 2,
               structs: 3,
               timestamp: 2,
               to_wire: 1,
               uniqueness: 2,
               version_requirement: 2
             )
  end

  defp exports(module) when is_atom(module), do: module.__info__(:functions) |> Enum.sort()
  defp exports(functions) when is_list(functions), do: Enum.sort(functions)
end
