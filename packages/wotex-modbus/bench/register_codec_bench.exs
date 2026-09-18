Code.require_file("support/frames.exs", __DIR__)

alias Wotex.Modbus.Bench.Frames
alias Wotex.Modbus.{Codec, Command}

tid = Frames.transaction_id()

inputs =
  Map.new(Frames.register_sizes(), fn {label, count} ->
    registers = Frames.registers(count)
    read = Frames.command!(:read_holding_registers, 0, count)
    write = Frames.command!(:write_holding_registers, 0, registers)
    response = Frames.read_registers_response(registers)
    {:ok, frame, ""} = Codec.decode(response)

    {label, %{registers: registers, read: read, write: write, response: response, frame: frame}}
  end)

Benchee.run(
  %{
    "admit write command" => fn %{registers: registers} ->
      {:ok, _} = Command.new(:write_holding_registers, 0, registers, 17)
    end,
    "encode read request" => fn %{read: read} -> {:ok, _} = Codec.encode(read, tid) end,
    "encode write request" => fn %{write: write} -> {:ok, _} = Codec.encode(write, tid) end,
    "decode response ADU" => fn %{response: response} ->
      {:ok, _, ""} = Codec.decode(response)
    end,
    "validate read response" => fn %{frame: frame, read: read} ->
      {:ok, [_ | _]} = Codec.response(frame, read, tid)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/register_codec.md",
     title: "# Register request encoding and response validation",
     description: """
     `Wotex.Modbus.Command.new/4` admission of a write multiple holding
     registers command (function 16), `Wotex.Modbus.Codec.encode/2` of the
     read holding registers (function 3) and function 16 requests, and
     `Wotex.Modbus.Codec.decode/1` and `Wotex.Modbus.Codec.response/3` of the
     function 3 response ADU, over one, 16 and 123 registers. 123 is the
     function 16 quantity limit. Response validation includes command
     revalidation, transaction and Unit Identifier correlation and the byte
     count check.
     """}
  ]
)
