Code.require_file("support/messages.exs", __DIR__)

alias Wotex.CoAP.Bench.Messages
alias Wotex.CoAP.{Block, Blockwise}

size = 512
path = [{11, "properties"}, {11, "log"}]
download = Messages.peer(23)
upload = Messages.peer(27)

inputs =
  Map.new(Messages.body_sizes(), fn {label, total} ->
    body = Messages.body(total)
    replies = Messages.download_replies(body, size)

    blocks =
      replies
      |> Enum.sort()
      |> Enum.map(fn {number, reply} ->
        {%Block{number: number, more: number < map_size(replies) - 1, size: size}, reply.payload}
      end)

    {label,
     %{
       get: Messages.request(1, path),
       put: Messages.request(3, [{12, <<42>>} | path], body),
       replies: replies,
       acks: Messages.upload_replies(total, size),
       blocks: blocks,
       total: total
     }}
  end)

Benchee.run(
  %{
    "Block2 download" => fn %{get: get, replies: replies, total: total} ->
      {{:ok, %{payload: <<_::binary-size(total)>>}}, _} =
        Blockwise.run(get, [block_size: size], replies, download)
    end,
    "Block1 upload" => fn %{put: put, acks: acks} ->
      {{:ok, %{code: 68}}, _} = Blockwise.run(put, [block_size: size], acks, upload)
    end,
    "Block.append/4 reassembly" => fn %{blocks: blocks, total: total} ->
      {:ok, <<_::binary-size(total)>>, :complete} =
        Enum.reduce(blocks, {:ok, <<>>, :more}, fn {block, payload}, {:ok, acc, :more} ->
          Block.append(acc, block, payload, 1_048_576)
        end)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/blockwise.md",
     title: "# RFC 7959 blockwise transfer",
     description: """
     `Wotex.CoAP.Blockwise.run/4` with 512-byte blocks over 1 KiB, 16 KiB and
     256 KiB bodies (two, 32 and 512 exchanges) against a pure in-process
     exchange function that returns precomputed replies, so no socket or timer
     is involved. The Block2 download validates every reply, its
     representation identity (status, ETag, Content-Format) and Size2 before
     appending; the Block1 upload splits the body and checks each 2.31 Continue
     acknowledgement. `Wotex.CoAP.Block.append/4` alone isolates the bounded
     sequential reassembly under the default 1 MiB body limit.
     """}
  ]
)
