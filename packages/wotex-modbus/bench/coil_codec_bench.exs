Code.require_file("support/frames.exs", __DIR__)

alias Wotex.Modbus.Bench.Frames
alias Wotex.Modbus.{Codec, Command}

tid = Frames.transaction_id()

inputs =
  Map.new(Frames.coil_sizes(), fn {label, count} ->
    coils = Frames.coils(count)
    read = Frames.command!(:read_coils, 0, count)
    write = Frames.command!(:write_coils, 0, coils)
    {:ok, frame, ""} = Codec.decode(Frames.read_coils_response(coils))
    {:ok, echo, ""} = Codec.decode(Frames.write_echo(write))
    {label, %{coils: coils, read: read, write: write, frame: frame, echo: echo}}
  end)

Benchee.run(
  %{
    "admit write command" => fn %{coils: coils} ->
      {:ok, _} = Command.new(:write_coils, 0, coils, 17)
    end,
    "encode write request" => fn %{write: write} -> {:ok, _} = Codec.encode(write, tid) end,
    "validate read response" => fn %{frame: frame, read: read} ->
      {:ok, [_ | _]} = Codec.response(frame, read, tid)
    end,
    "validate write echo" => fn %{echo: echo, write: write} ->
      {:ok, :written} = Codec.response(echo, write, tid)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/coil_codec.md",
     title: "# Coil bit packing and response validation",
     description: """
     `Wotex.Modbus.Command.new/4` admission and `Wotex.Modbus.Codec.encode/2`
     of a write multiple coils command (function 15, bit packing), and
     `Wotex.Modbus.Codec.response/3` of the read coils (function 1) response,
     which checks the byte count before unpacking one boolean per coil, and of
     the function 15 echo, over eight, 256 and 1968 coils. 1968 is the function
     15 quantity limit.
     """}
  ]
)
