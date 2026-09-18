Code.require_file("support/records.exs", __DIR__)

alias Wotex.Lab.Bench.Records
alias Wotex.Lab.Evidence.{Digest, Record}

inputs = Map.new(Records.sizes(), fn {label, count} -> {label, Records.input(count)} end)

Benchee.run(
  %{
    "new: validate and scan" => fn %{fields: fields, record: record} ->
      {:ok, ^record} = Record.new(fields)
    end,
    "from_map: read back" => fn %{map: map, record: record} ->
      {:ok, ^record} = Record.from_map(map)
    end,
    "digest: canonical encoding and SHA-256" => fn %{record: record, digest: digest} ->
      {:ok, ^digest} = Record.digest(record)
    end,
    "digest the fixture tree" => fn %{tree: tree, tree_digest: tree_digest} ->
      {:ok, ^tree_digest} = Digest.tree(tree, ["**/*.json"])
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/evidence_record.md",
     title: "# Evidence record admission, canonical digests and fixture trees",
     description: """
     `Wotex.Lab.Evidence.Record` and `Wotex.Lab.Evidence.Digest` over run
     records with 8, 128 and 1,024 fixture digests, input references and
     assertions (1,024 is the record's collection bound), 24 dependencies
     (the eight WoTEx packages with `archive: :missing`, 16 Hex packages with
     an archive digest), the default runner budgets and this host's
     toolchain strings. The fixtures are files of about 2 KiB in seven lane
     directories of a temporary tree.

     `new: validate and scan` is `Wotex.Lab.Evidence.Record.new/1`: every
     field's shape and bound, the `sha256:` form of every digest, and the
     scan of every value for callbacks, process identities, filesystem paths
     and credential material. `from_map: read back` is
     `Wotex.Lab.Evidence.Record.from_map/1` on the record's string-keyed map,
     which reads keys back only as existing atoms and validates again.
     `digest: canonical encoding and SHA-256` is
     `Wotex.Lab.Evidence.Record.digest/1`:
     `Wotex.Lab.Evidence.Record.to_map/1`, the canonical encoding with
     `Wotex.JSON.encode/1` and the SHA-256 of the bytes. `digest the fixture
     tree` is `Wotex.Lab.Evidence.Digest.tree/2`: reading and digesting every
     fixture file and hashing the sorted `path\\0digest` lines. Every job
     compares its result with the value computed before the run.
     """}
  ]
)

File.rm_rf!(Records.root())
