Code.require_file("support/values.exs", __DIR__)

alias WotexContinuum.Bench.Values
alias WotexContinuum.{Compatibility, Manifest}

inputs =
  Map.new(
    %{"1 capability" => 1, "16 capabilities" => 16, "128 capabilities" => 128},
    fn {label, count} ->
      map = Values.manifest(count)
      {:ok, manifest} = Manifest.from_map(map)

      {label,
       %{
         count: count,
         map: map,
         manifest: manifest,
         satisfied: Values.capabilities(count, "2.4.1"),
         outdated: Values.capabilities(count, "1.9.0")
       }}
    end
  )

Benchee.run(
  %{
    "Manifest.from_map" => fn %{map: map} -> {:ok, %Manifest{}} = Manifest.from_map(map) end,
    "compatible_with? (every requirement met)" => fn %{manifest: manifest, satisfied: declared} ->
      :ok = Manifest.compatible_with?(manifest, "2.0.7", declared)
    end,
    "Compatibility.evaluate (every requirement mismatched)" => fn input ->
      %{manifest: manifest, outdated: declared, count: count} = input

      {:error, mismatches} =
        Compatibility.evaluate(manifest.compatibility, "2.0.7", declared)

      ^count = length(mismatches)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/compatibility.md",
     title: "# Manifest construction and compatibility evaluation",
     description: """
     A `continuum_manifest` that declares one, 16 or 128 capabilities and requires
     each of them with `~> 2.0`. `WotexContinuum.Manifest.from_map/1` constructs
     and validates the manifest from its decoded map.
     `WotexContinuum.Manifest.compatible_with?/3` evaluates schema version 2.0.7
     against consumer capabilities at version 2.4.1, which meet every requirement.
     `WotexContinuum.Compatibility.evaluate/3` runs against capabilities at
     version 1.9.0 and is expected to return one `capability_version` mismatch
     per requirement, the complete report the contract promises.
     """}
  ]
)
