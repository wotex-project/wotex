defmodule WotexWorkspace.NativeArtifactELFFixture do
  @moduledoc false

  @base 0x400000

  @spec write!(Path.t(), keyword()) :: Path.t()
  def write!(path, opts \\ []) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes(opts))
    path
  end

  @spec bytes(keyword()) :: binary()
  def bytes(opts \\ []) do
    class = Keyword.get(opts, :class, "elf64")
    endian = Keyword.get(opts, :endianness, "little")
    interpreter = Keyword.get(opts, :interpreter)
    needed = Keyword.get(opts, :needed, [])
    soname = Keyword.get(opts, :soname)
    dynamic? = needed != [] or not is_nil(soname)
    layout = layout(class)
    program_count = 1 + present(interpreter) + present(dynamic?)
    table_end = layout.header_size + program_count * layout.program_size
    data_start = align(table_end, 0x100)

    {interpreter_offset, after_interpreter, interpreter_bytes} =
      component(interpreter && interpreter <> <<0>>, data_start)

    {string_table, offsets} = string_table(needed ++ List.wrap(soname))
    string_offset = align(after_interpreter, 0x40)
    dynamic_offset = align(string_offset + byte_size(string_table), 0x40)

    dynamic =
      if dynamic? do
        dynamic_table(layout, endian, string_offset, string_table, needed, soname, offsets)
      else
        <<>>
      end

    total =
      [
        table_end,
        after_interpreter,
        string_offset + byte_size(string_table),
        dynamic_offset + byte_size(dynamic)
      ]
      |> Enum.max()
      |> align(0x100)

    header =
      header(
        layout,
        endian,
        Keyword.get(opts, :architecture, "x86_64"),
        Keyword.get(opts, :type, if(interpreter, do: "executable", else: "shared")),
        program_count
      )

    programs =
      [load_program(layout, endian, total)] ++
        optional_program(layout, endian, 3, interpreter_offset, byte_size(interpreter_bytes)) ++
        optional_program(layout, endian, 2, dynamic_offset, byte_size(dynamic))

    header
    |> Kernel.<>(IO.iodata_to_binary(programs))
    |> pad_to(data_start)
    |> Kernel.<>(interpreter_bytes)
    |> pad_to(string_offset)
    |> Kernel.<>(string_table)
    |> pad_to(dynamic_offset)
    |> Kernel.<>(dynamic)
    |> pad_to(total)
  end

  defp layout("elf32"), do: %{class: 1, word: 4, header_size: 52, program_size: 32}
  defp layout("elf64"), do: %{class: 2, word: 8, header_size: 64, program_size: 56}

  defp header(layout, endian, architecture, type, program_count) do
    ident = <<0x7F, "ELF", layout.class, endian_code(endian), 1, 0, 0, 0::size(7 * 8)>>

    fields =
      if layout.class == 1 do
        [
          integer(type_code(type), 2, endian),
          integer(machine(architecture), 2, endian),
          integer(1, 4, endian),
          integer(0, 4, endian),
          integer(layout.header_size, 4, endian),
          integer(0, 4, endian),
          integer(0, 4, endian),
          integer(layout.header_size, 2, endian),
          integer(layout.program_size, 2, endian),
          integer(program_count, 2, endian),
          integer(0, 2, endian),
          integer(0, 2, endian),
          integer(0, 2, endian)
        ]
      else
        [
          integer(type_code(type), 2, endian),
          integer(machine(architecture), 2, endian),
          integer(1, 4, endian),
          integer(0, 8, endian),
          integer(layout.header_size, 8, endian),
          integer(0, 8, endian),
          integer(0, 4, endian),
          integer(layout.header_size, 2, endian),
          integer(layout.program_size, 2, endian),
          integer(program_count, 2, endian),
          integer(0, 2, endian),
          integer(0, 2, endian),
          integer(0, 2, endian)
        ]
      end

    IO.iodata_to_binary([ident | fields])
  end

  defp load_program(layout, endian, total) do
    program(layout, endian, 1, 5, 0, @base, total, total)
  end

  defp optional_program(_, _, _, _, 0), do: []

  defp optional_program(layout, endian, type, offset, size) do
    [program(layout, endian, type, 4, offset, @base + offset, size, size)]
  end

  defp program(%{class: 1}, endian, type, flags, offset, address, file_size, memory_size) do
    IO.iodata_to_binary([
      integer(type, 4, endian),
      integer(offset, 4, endian),
      integer(address, 4, endian),
      integer(address, 4, endian),
      integer(file_size, 4, endian),
      integer(memory_size, 4, endian),
      integer(flags, 4, endian),
      integer(0x1000, 4, endian)
    ])
  end

  defp program(_, endian, type, flags, offset, address, file_size, memory_size) do
    IO.iodata_to_binary([
      integer(type, 4, endian),
      integer(flags, 4, endian),
      integer(offset, 8, endian),
      integer(address, 8, endian),
      integer(address, 8, endian),
      integer(file_size, 8, endian),
      integer(memory_size, 8, endian),
      integer(0x1000, 8, endian)
    ])
  end

  defp dynamic_table(layout, endian, string_offset, table, needed, soname, offsets) do
    entries =
      List.flatten([
        [{5, @base + string_offset}, {10, byte_size(table)}],
        Enum.map(needed, &{1, Map.fetch!(offsets, &1)}),
        if(soname, do: [{14, Map.fetch!(offsets, soname)}], else: []),
        [{0, 0}]
      ])

    IO.iodata_to_binary(
      Enum.map(entries, fn {tag, value} ->
        [integer(tag, layout.word, endian), integer(value, layout.word, endian)]
      end)
    )
  end

  defp string_table(names) do
    names
    |> Enum.uniq()
    |> Enum.reduce({<<0>>, %{}}, fn name, {bytes, offsets} ->
      {bytes <> name <> <<0>>, Map.put(offsets, name, byte_size(bytes))}
    end)
  end

  defp component(nil, offset), do: {0, offset, <<>>}
  defp component(bytes, offset), do: {offset, offset + byte_size(bytes), bytes}

  defp present(value) when value in [nil, false], do: 0
  defp present(_), do: 1

  defp pad_to(bytes, offset) when byte_size(bytes) <= offset do
    bytes <> <<0::size((offset - byte_size(bytes)) * 8)>>
  end

  defp align(value, boundary), do: div(value + boundary - 1, boundary) * boundary

  defp integer(value, size, "little"), do: <<value::unsigned-little-size(size * 8)>>
  defp integer(value, size, "big"), do: <<value::unsigned-big-size(size * 8)>>

  defp endian_code("little"), do: 1
  defp endian_code("big"), do: 2

  defp machine("x86"), do: 3
  defp machine("arm"), do: 40
  defp machine("x86_64"), do: 62
  defp machine("aarch64"), do: 183
  defp machine("riscv64"), do: 243

  defp type_code("executable"), do: 2
  defp type_code("shared"), do: 3
end
