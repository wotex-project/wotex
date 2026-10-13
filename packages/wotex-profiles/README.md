# Wotex Profiles

Wotex Profiles reads bounded external profiles and consumer-supplied semantic
descriptors, with deterministic identities and exact rational unit coordinates.

Wotex Profiles is a passive library in the WoTEx family. Consumers own profile
data, installed protocol bindings, trust, device qualification and effects.
Reading a document does not enroll a Thing or authorize an interaction.

## Installation

Wotex Profiles 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.18 through Elixir
1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
Add it to your dependencies:

```elixir
def deps do
  [
    {:wotex_profiles, "~> 0.1"}
  ]
end
```

## Reading a descriptor

Supply all eight limits explicitly. `Definition.parse/2` returns a checked
value or a fixed `Wotex.Profiles.Error` with a safe pointer. It retains the
original-byte digest separately from its annotation-free semantic digest.

```elixir
limits = %{
  "max_bytes" => 65_536, "max_depth" => 16, "max_nodes" => 4096,
  "max_channels" => 64, "max_definitions" => 64, "max_bindings" => 8,
  "max_dependencies" => 128, "max_numeric_digits" => 64
}

{:ok, descriptor} = Wotex.Profiles.Definition.parse(original_bytes, limits)
{:ok, reference} = Wotex.Profiles.Definition.reference(descriptor, limits)
```

`Profile.new/2`, `Definition.new/2` and `Unit.new/2` also accept native values
and revalidate them. Native reconstruction recomputes semantic identity and
clears raw identity; it cannot prove custody of original bytes. References
never fetch a URL or select executable code. JSON numeric thresholds that
would round during normalization refuse `numeric_limit`.

The reader supports the closed mechanical DataSchema subset in
[the external-profile contract](../../docs/packages/wotex-profiles/specs/WPF.01-external-profile-language.md).
`Unit.convert/4` supplies exact rational conversion between matching quantity
URI/dimension pairs and refuses repeating fractions or arithmetic overflow.
`Binding.digest/2` and `Binding.new/2` prepare and verify explicit installed
selector/raw-value registrations. Digest verification does not qualify a decoder
or device, and a reference never loads its implementation.
Compilation, capture matching, report interpretation and authoring are separate
planned contracts; the package catalogue records their current evidence.

## Development

The [completion contract](../../docs/packages/wotex-profiles/plans/wotex-profiles-completion.md)
and the specification catalogue
(`docs/packages/wotex-profiles/specs/catalogue.yaml`) define the package's
obligations. Local execution tracking is not part of the published
contract.

Run commands from the repository root; the
[contributing guide](https://github.com/wotex-project/wotex/blob/main/CONTRIBUTING.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-profiles test test/wotex/profiles_test.exs  # one test file
mix check.fast --package wotex-profiles                   # compile, format, Credo, tests
mix pkg wotex-profiles check --no-retry                   # full gate
```

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-profiles`. It compiles with warnings as errors, checks the lock and
unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`,
Credo, Doctor, `mix docs --warnings-as-errors` (in the `docs` environment),
tests with the 95% coverage floor (`mix coveralls`), Dialyzer, the boundary
scan (`elixir bin/check_boundary.exs`) and `git diff --check`, then runs the
archive check (`bin/check_archive.exs`) and the application-free check
(`bin/check_application_free.exs`). This package has no native build,
software profile or container lane.

## License

Wotex Profiles is released under the
[Apache License 2.0](https://github.com/wotex-project/wotex/blob/main/packages/wotex-profiles/LICENSE).
