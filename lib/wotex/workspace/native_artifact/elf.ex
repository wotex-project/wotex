defmodule Wotex.Workspace.NativeArtifact.ELF do
  @moduledoc """
  Bounded inspection of ELF target identity and dynamic dependencies.

  The reader uses the ELF program-header and dynamic tables directly. It does
  not execute the file, invoke a host linker, consult host search paths or rely
  on section headers that may be absent from stripped production artifacts.
  """

  @max_bytes 536_870_912
  @max_program_headers 4_096
  @max_dynamic_entries 65_536
  @max_string_table 16_777_216
  @max_interpreter 4_096

  @type t :: %__MODULE__{
          path: Path.t(),
          class: String.t(),
          architecture: String.t(),
          endianness: String.t(),
          type: String.t(),
          interpreter: String.t() | nil,
          needed: [String.t()],
          soname: String.t() | nil,
          sha256: String.t()
        }

  @enforce_keys [
    :path,
    :class,
    :architecture,
    :endianness,
    :type,
    :interpreter,
    :needed,
    :soname,
    :sha256
  ]
  defstruct @enforce_keys

  @doc "Inspects one ordinary ELF file under an explicit byte bound."
  @spec inspect(Path.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def inspect(path, opts \\ []) do
    maximum = Keyword.get(opts, :max_bytes, @max_bytes)

    with :ok <- positive_bound(maximum),
         {:ok, size} <- ordinary_file(path, maximum),
         {:ok, io} <- open(path) do
      try do
        inspect_open(%{io: io, size: size}, path)
      after
        File.close(io)
      end
    end
  end

  @doc "Returns whether an ordinary file starts with the ELF magic."
  @spec file?(Path.t()) :: boolean()
  def file?(path) do
    with {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, io} <- File.open(path, [:read, :binary]) do
      result = :file.pread(io, 0, 4) == {:ok, <<0x7F, "ELF">>}
      File.close(io)
      result
    else
      _ -> false
    end
  end

  defp inspect_open(reader, path) do
    with {:ok, identification} <- read(reader, 0, 16, "ELF identification"),
         {:ok, layout} <- layout(identification),
         {:ok, header} <- read(reader, 0, layout.header_size, "ELF header"),
         {:ok, metadata} <- header_metadata(header, layout),
         {:ok, programs} <- program_headers(reader, metadata, layout),
         {:ok, interpreter} <- interpreter(reader, programs),
         {:ok, dynamic} <- dynamic(reader, programs, layout),
         {:ok, strings} <- dynamic_strings(reader, programs, dynamic),
         {:ok, digest} <- digest(reader) do
      {:ok,
       %__MODULE__{
         path: path,
         class: layout.class,
         architecture: architecture(metadata.machine, layout.class),
         endianness: layout.endianness,
         type: object_type(metadata.type),
         interpreter: interpreter,
         needed: strings.needed,
         soname: strings.soname,
         sha256: digest
       }}
    end
  end

  defp layout(<<0x7F, "ELF", class, data, 1, _, _, _::binary-size(7), _::binary>>) do
    with {:ok, class_name, word, header_size, program_size} <- class(class),
         {:ok, endianness} <- endianness(data) do
      {:ok,
       %{
         class: class_name,
         word: word,
         header_size: header_size,
         program_size: program_size,
         endianness: endianness
       }}
    end
  end

  defp layout(_), do: {:error, "file is not a supported ELF object"}

  defp class(1), do: {:ok, "elf32", 4, 52, 32}
  defp class(2), do: {:ok, "elf64", 8, 64, 56}
  defp class(_), do: {:error, "ELF class is unsupported"}

  defp endianness(1), do: {:ok, "little"}
  defp endianness(2), do: {:ok, "big"}
  defp endianness(_), do: {:error, "ELF endianness is unsupported"}

  defp header_metadata(header, %{class: "elf32"} = layout) do
    metadata = %{
      type: unsigned(header, 16, 2, layout.endianness),
      machine: unsigned(header, 18, 2, layout.endianness),
      version: unsigned(header, 20, 4, layout.endianness),
      program_offset: unsigned(header, 28, 4, layout.endianness),
      header_size: unsigned(header, 40, 2, layout.endianness),
      program_size: unsigned(header, 42, 2, layout.endianness),
      program_count: unsigned(header, 44, 2, layout.endianness)
    }

    validate_header(metadata, layout)
  end

  defp header_metadata(header, layout) do
    metadata = %{
      type: unsigned(header, 16, 2, layout.endianness),
      machine: unsigned(header, 18, 2, layout.endianness),
      version: unsigned(header, 20, 4, layout.endianness),
      program_offset: unsigned(header, 32, 8, layout.endianness),
      header_size: unsigned(header, 52, 2, layout.endianness),
      program_size: unsigned(header, 54, 2, layout.endianness),
      program_count: unsigned(header, 56, 2, layout.endianness)
    }

    validate_header(metadata, layout)
  end

  defp validate_header(metadata, layout) do
    cond do
      metadata.version != 1 ->
        {:error, "ELF header version is unsupported"}

      metadata.header_size != layout.header_size ->
        {:error, "ELF header has a non-canonical size"}

      metadata.program_count == 0xFFFF ->
        {:error, "ELF extended program-header counts are unsupported"}

      metadata.program_count > @max_program_headers ->
        {:error, "ELF exceeds #{@max_program_headers} program headers"}

      metadata.program_count > 0 and metadata.program_size != layout.program_size ->
        {:error, "ELF program-header size is invalid"}

      true ->
        {:ok, metadata}
    end
  end

  defp program_headers(_, %{program_count: 0}, _), do: {:ok, []}

  defp program_headers(reader, metadata, layout) do
    size = metadata.program_count * metadata.program_size

    with {:ok, table} <- read(reader, metadata.program_offset, size, "ELF program-header table") do
      programs =
        for index <- 0..(metadata.program_count - 1) do
          offset = index * metadata.program_size
          parse_program(binary_part(table, offset, metadata.program_size), layout)
        end

      {:ok, programs}
    end
  end

  defp parse_program(bytes, %{class: "elf32", endianness: endian}) do
    %{
      type: unsigned(bytes, 0, 4, endian),
      offset: unsigned(bytes, 4, 4, endian),
      virtual_address: unsigned(bytes, 8, 4, endian),
      file_size: unsigned(bytes, 16, 4, endian),
      memory_size: unsigned(bytes, 20, 4, endian),
      flags: unsigned(bytes, 24, 4, endian)
    }
  end

  defp parse_program(bytes, %{endianness: endian}) do
    %{
      type: unsigned(bytes, 0, 4, endian),
      flags: unsigned(bytes, 4, 4, endian),
      offset: unsigned(bytes, 8, 8, endian),
      virtual_address: unsigned(bytes, 16, 8, endian),
      file_size: unsigned(bytes, 32, 8, endian),
      memory_size: unsigned(bytes, 40, 8, endian)
    }
  end

  defp interpreter(reader, programs) do
    case Enum.filter(programs, &(&1.type == 3)) do
      [] ->
        {:ok, nil}

      [program] when program.file_size <= @max_interpreter ->
        with {:ok, bytes} <- read(reader, program.offset, program.file_size, "ELF interpreter"),
             {:ok, path} <- terminated_string(bytes, "ELF interpreter") do
          validate_interpreter(path)
        end

      [_] ->
        {:error, "ELF interpreter exceeds #{@max_interpreter} bytes"}

      _ ->
        {:error, "ELF contains more than one interpreter"}
    end
  end

  defp validate_interpreter(path) do
    components = String.split(path, "/", trim: false)

    if String.valid?(path) and Path.type(path) == :absolute and
         Enum.all?(tl(components), &(&1 not in ["", ".", ".."])) do
      {:ok, path}
    else
      {:error, "ELF interpreter is not a normalized absolute UTF-8 path"}
    end
  end

  defp dynamic(reader, programs, layout) do
    case Enum.filter(programs, &(&1.type == 2)) do
      [] ->
        {:ok, %{needed: [], soname: [], string_address: [], string_size: []}}

      [program] ->
        dynamic_entries(reader, program, layout)

      _ ->
        {:error, "ELF contains more than one dynamic segment"}
    end
  end

  defp dynamic_entries(reader, program, layout) do
    entry_size = layout.word * 2

    cond do
      rem(program.file_size, entry_size) != 0 ->
        {:error, "ELF dynamic segment has a partial entry"}

      div(program.file_size, entry_size) > @max_dynamic_entries ->
        {:error, "ELF exceeds #{@max_dynamic_entries} dynamic entries"}

      true ->
        with {:ok, bytes} <- read(reader, program.offset, program.file_size, "ELF dynamic segment") do
          parse_dynamic(bytes, layout, entry_size)
        end
    end
  end

  defp parse_dynamic(bytes, layout, entry_size) do
    entries =
      bytes
      |> chunks(entry_size)
      |> Enum.map(fn entry ->
        {
          unsigned(entry, 0, layout.word, layout.endianness),
          unsigned(entry, layout.word, layout.word, layout.endianness)
        }
      end)

    case Enum.split_while(entries, fn {tag, _} -> tag != 0 end) do
      {_, []} ->
        {:error, "ELF dynamic segment has no terminating entry"}

      {active, _} ->
        {:ok,
         %{
           needed: values(active, 1),
           string_address: values(active, 5),
           string_size: values(active, 10),
           soname: values(active, 14)
         }}
    end
  end

  defp dynamic_strings(_, _, %{needed: [], soname: []}) do
    {:ok, %{needed: [], soname: nil}}
  end

  defp dynamic_strings(reader, programs, dynamic) do
    with {:ok, address} <- exactly_one(dynamic.string_address, "DT_STRTAB"),
         {:ok, size} <- exactly_one(dynamic.string_size, "DT_STRSZ"),
         :ok <- string_table_bound(size),
         {:ok, offset} <- virtual_offset(programs, address, size),
         {:ok, table} <- read(reader, offset, size, "ELF dynamic string table"),
         {:ok, needed} <- names(table, dynamic.needed, "DT_NEEDED"),
         {:ok, soname} <- optional_name(table, dynamic.soname, "DT_SONAME") do
      {:ok, %{needed: needed, soname: soname}}
    end
  end

  defp exactly_one([value], _), do: {:ok, value}
  defp exactly_one([], tag), do: {:error, "ELF dynamic segment is missing #{tag}"}
  defp exactly_one(_, tag), do: {:error, "ELF dynamic segment repeats #{tag}"}

  defp string_table_bound(size) when size > 0 and size <= @max_string_table, do: :ok

  defp string_table_bound(_),
    do: {:error, "ELF dynamic string table has an invalid size"}

  defp virtual_offset(programs, address, size) do
    offsets =
      programs
      |> Enum.filter(fn program ->
        program.type == 1 and address >= program.virtual_address and
          address + size <= program.virtual_address + program.file_size
      end)
      |> Enum.map(&(address - &1.virtual_address + &1.offset))
      |> Enum.uniq()

    case offsets do
      [offset] -> {:ok, offset}
      [] -> {:error, "ELF dynamic string table is not backed by a load segment"}
      _ -> {:error, "ELF dynamic string table has ambiguous load mappings"}
    end
  end

  defp names(table, offsets, tag) do
    offsets
    |> Enum.reduce_while({:ok, []}, fn offset, {:ok, names} ->
      case name(table, offset, tag) do
        {:ok, value} -> {:cont, {:ok, [value | names]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> reverse_names()
  end

  defp reverse_names({:ok, names}), do: {:ok, Enum.reverse(names)}
  defp reverse_names({:error, _} = error), do: error

  defp optional_name(_, [], _), do: {:ok, nil}

  defp optional_name(table, [offset], tag), do: name(table, offset, tag)

  defp optional_name(_, _, tag), do: {:error, "ELF dynamic segment repeats #{tag}"}

  defp name(table, offset, tag) when offset < byte_size(table) do
    bytes = binary_part(table, offset, byte_size(table) - offset)

    case :binary.match(bytes, <<0>>) do
      {length, 1} -> validate_name(binary_part(bytes, 0, length), tag)
      :nomatch -> {:error, "ELF #{tag} string is not terminated"}
    end
  end

  defp name(_, _, tag), do: {:error, "ELF #{tag} offset is outside the string table"}

  defp validate_name(name, tag) do
    if name != "" and String.valid?(name) and Path.basename(name) == name and
         not String.contains?(name, <<0>>) do
      {:ok, name}
    else
      {:error, "ELF #{tag} is not a plain UTF-8 library name"}
    end
  end

  defp terminated_string(bytes, label) when byte_size(bytes) > 0 do
    content_size = byte_size(bytes) - 1

    case bytes do
      <<content::binary-size(^content_size), 0>> ->
        if String.contains?(content, <<0>>),
          do: {:error, "#{label} contains an embedded terminator"},
          else: {:ok, content}

      _ ->
        {:error, "#{label} is not terminated"}
    end
  end

  defp terminated_string(_, label), do: {:error, "#{label} is empty"}

  defp digest(reader), do: digest(reader, 0, :crypto.hash_init(:sha256))

  defp digest(%{size: size}, size, context) do
    raw = :crypto.hash_final(context)
    {:ok, Base.encode16(raw, case: :lower)}
  end

  defp digest(reader, offset, context) do
    length = min(65_536, reader.size - offset)

    with {:ok, bytes} <- read(reader, offset, length, "ELF content") do
      digest(reader, offset + length, :crypto.hash_update(context, bytes))
    end
  end

  defp read(_, _, 0, _), do: {:ok, <<>>}

  defp read(reader, offset, length, label)
       when is_integer(offset) and is_integer(length) and offset >= 0 and length >= 0 do
    if offset + length <= reader.size do
      case :file.pread(reader.io, offset, length) do
        {:ok, bytes} when byte_size(bytes) == length -> {:ok, bytes}
        {:ok, _} -> {:error, "#{label} ended before its declared size"}
        :eof -> {:error, "#{label} is outside the file"}
        {:error, reason} -> {:error, "#{label}: #{:file.format_error(reason)}"}
      end
    else
      {:error, "#{label} is outside the file"}
    end
  end

  defp unsigned(bytes, offset, length, endianness) do
    value = binary_part(bytes, offset, length)
    decode_unsigned(value, endianness)
  end

  defp decode_unsigned(value, "little"), do: :binary.decode_unsigned(value, :little)
  defp decode_unsigned(value, "big"), do: :binary.decode_unsigned(value, :big)

  defp chunks(<<>>, _), do: []

  defp chunks(bytes, size) do
    <<entry::binary-size(^size), rest::binary>> = bytes
    [entry | chunks(rest, size)]
  end

  defp values(entries, tag), do: for({^tag, value} <- entries, do: value)

  defp architecture(3, _), do: "x86"
  defp architecture(40, _), do: "arm"
  defp architecture(62, _), do: "x86_64"
  defp architecture(183, _), do: "aarch64"
  defp architecture(243, "elf32"), do: "riscv32"
  defp architecture(243, "elf64"), do: "riscv64"
  defp architecture(machine, _), do: "machine-#{machine}"

  defp object_type(2), do: "executable"
  defp object_type(3), do: "shared"
  defp object_type(type), do: "type-#{type}"

  defp ordinary_file(path, maximum) do
    if is_binary(path) and Path.type(path) == :absolute,
      do: stat_file(path, maximum),
      else: {:error, "ELF path must be absolute"}
  end

  defp stat_file(path, maximum) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} when size <= maximum ->
        {:ok, size}

      {:ok, %{type: :regular}} ->
        {:error, "ELF exceeds #{maximum} bytes"}

      {:ok, %{type: type}} ->
        {:error, "ELF path is #{type}, expected regular file"}

      {:error, reason} ->
        {:error, "ELF path: #{:file.format_error(reason)}"}
    end
  end

  defp open(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, io} -> {:ok, io}
      {:error, reason} -> {:error, "ELF path: #{:file.format_error(reason)}"}
    end
  end

  defp positive_bound(value) when is_integer(value) and value > 0 and value <= @max_bytes,
    do: :ok

  defp positive_bound(_), do: {:error, "ELF byte bound must be from 1 through #{@max_bytes}"}
end
