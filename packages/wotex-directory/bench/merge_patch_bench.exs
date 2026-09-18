Code.require_file("support/things.exs", __DIR__)
Code.require_file("support/snapshot_ports.exs", __DIR__)

alias Wotex.Directory
alias Wotex.Directory.Bench.{SnapshotPorts, Things}
alias Wotex.Directory.{Context, MergePatch, Mutation}

context = Context.new!("urn:example:principal:operator")
registered = Things.identifier(1)

inputs =
  Map.new(Things.sizes(), fn {label, count} ->
    stored = Things.thing_description(registered, count)
    service = SnapshotPorts.service([SnapshotPorts.entry(stored)], Things.introduction())

    {label,
     %{
       service: service,
       target: Things.document(registered, count),
       patch: Things.merge_patch(count)
     }}
  end)

Benchee.run(
  %{
    "MergePatch.apply" => fn %{target: target, patch: patch} ->
      {:ok, _} = MergePatch.apply(target, patch)
    end,
    "Directory.patch (merge, revalidation, replacement)" => fn %{service: service, patch: patch} ->
      {:ok, %Mutation{status: :patched}} = Directory.patch(service, registered, patch, context)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/merge_patch.md",
     title: "# Bounded JSON Merge Patch",
     description: """
     A JSON Merge Patch that renames the Thing and adds a `description` and a
     `minimum` to every Property, applied to synthetic Thing Descriptions with
     one, 24 and 240 Properties. `Wotex.Directory.MergePatch.apply/3` measures
     the bounded RFC 7396 merge alone with the default depth and node limits;
     `Wotex.Directory.patch/5` adds authorization, retrieval from an in-process
     snapshot repository, Discovery enrichment, revalidation of the merged Thing
     Description, registration reconstruction and the conditional replacement.
     """}
  ]
)
