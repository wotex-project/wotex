defmodule Wotex.Workspace.NativeArtifact.Archive do
  @moduledoc """
  A bounded, read-only scanner for the WoTEx native artifact tar format.

  The scanner never invokes a system archiver and never writes archive entries
  to disk. Plain tar and one gzip stream are accepted. Entry metadata and file
  digests are produced incrementally under explicit resource limits.
  """

  import Bitwise

  alias Wotex.Workspace.NativeArtifact.PayloadManifest

  @manifest_path "artifact-manifest.json"
  @block_size 512

  defmodule Limits do
    @moduledoc "Resource limits applied before and while scanning an archive."

    @type t :: %__MODULE__{
            compressed_bytes: pos_integer(),
            expanded_bytes: pos_integer(),
            expansion_ratio: pos_integer(),
            entries: pos_integer(),
            file_bytes: pos_integer(),
            path_bytes: pos_integer(),
            path_depth: pos_integer(),
            manifest_bytes: pos_integer()
          }

    defstruct compressed_bytes: 536_870_912,
              expanded_bytes: 1_073_741_824,
              expansion_ratio: 256,
              entries: 100_000,
              file_bytes: 536_870_912,
              path_bytes: 1_024,
              path_depth: 64,
              manifest_bytes: 1_048_576
  end

  defmodule Scan do
    @moduledoc "Verified archive metadata before payload-manifest comparison."

    @enforce_keys [
      :entries,
      :manifest_bytes,
      :compressed_size,
      :expanded_size,
      :transport_sha256
    ]
    defstruct @enforce_keys
  end

  defmodule Parser do
    @moduledoc false

    defstruct phase: :header,
              buffer: <<>>,
              zero_blocks: 0,
              current: nil,
              remaining: 0,
              padding: 0,
              entries: [],
              paths: MapSet.new(),
              manifest_bytes: nil,
              entry_count: 0
  end

  @doc "The required name of the manifest entry inside an artifact archive."
  @spec manifest_path() :: String.t()
  def manifest_path, do: @manifest_path

  @doc "Scans one ordinary archive file without extracting it."
  @spec scan(Path.t(), Limits.t()) :: {:ok, Scan.t()} | {:error, String.t()}
  def scan(path, %Limits{} = limits \\ %Limits{}) do
    with :ok <- validate_limits(limits),
         {:ok, stat} <- ordinary_file(path),
         :ok <- compressed_bound(stat.size, limits),
         {:ok, encoding} <- encoding(path),
         {:ok, parser, expanded, transport_digest} <- stream(path, encoding, stat.size, limits),
         {:ok, entries, manifest_bytes} <- finish(parser) do
      {:ok,
       %Scan{
         entries: entries,
         manifest_bytes: manifest_bytes,
         compressed_size: stat.size,
         expanded_size: expanded,
         transport_sha256: transport_digest
       }}
    end
  end

  defp validate_limits(limits) do
    invalid =
      limits
      |> Map.from_struct()
      |> Enum.reject(fn {_, value} -> is_integer(value) and value > 0 end)

    if invalid == [],
      do: :ok,
      else: {:error, "archive limits must be positive integers: #{inspect(Enum.sort(invalid))}"}
  end

  defp stream(path, :tar, compressed_size, limits) do
    case File.open(path, [:read, :binary]) do
      {:ok, io} ->
        try do
          read_plain(io, %Parser{}, 0, :crypto.hash_init(:sha256), compressed_size, limits)
        after
          File.close(io)
        end

      {:error, reason} ->
        {:error, "archive: #{:file.format_error(reason)}"}
    end
  end

  defp stream(path, :gzip, compressed_size, limits) do
    case File.open(path, [:read, :binary]) do
      {:ok, io} ->
        zlib = :zlib.open()

        try do
          :ok = :zlib.inflateInit(zlib, 31)

          read_gzip(
            io,
            zlib,
            %Parser{},
            0,
            :crypto.hash_init(:sha256),
            compressed_size,
            limits,
            :continue,
            0
          )
        catch
          :error, reason -> {:error, "invalid gzip stream: #{inspect(reason)}"}
        after
          _ = safe_inflate_end(zlib)
          :zlib.close(zlib)
          File.close(io)
        end

      {:error, reason} ->
        {:error, "archive: #{:file.format_error(reason)}"}
    end
  end

  defp read_plain(io, parser, expanded, digest, compressed_size, limits) do
    case IO.binread(io, 65_536) do
      :eof ->
        {:ok, parser, expanded, final_digest(digest)}

      {:error, reason} ->
        {:error, "archive read failed: #{:file.format_error(reason)}"}

      bytes ->
        with :ok <- expanded_bound(expanded + byte_size(bytes), compressed_size, :tar, limits),
             {:ok, next_parser} <- feed(parser, bytes, limits) do
          read_plain(
            io,
            next_parser,
            expanded + byte_size(bytes),
            :crypto.hash_update(digest, bytes),
            compressed_size,
            limits
          )
        end
    end
  end

  defp read_gzip(io, zlib, parser, expanded, digest, compressed_size, limits, status, crc) do
    case IO.binread(io, 4_096) do
      :eof ->
        finish_gzip(io, zlib, parser, expanded, digest, compressed_size, limits, status, crc)

      {:error, reason} ->
        {:error, "archive read failed: #{:file.format_error(reason)}"}

      bytes ->
        case :zlib.safeInflate(zlib, bytes) do
          {next_status, output} when next_status in [:continue, :finished] ->
            with {:ok, next_parser, next_expanded, next_crc} <-
                   feed_inflated(parser, output, expanded, crc, compressed_size, limits) do
              read_gzip(
                io,
                zlib,
                next_parser,
                next_expanded,
                :crypto.hash_update(digest, bytes),
                compressed_size,
                limits,
                next_status,
                next_crc
              )
            end

          other ->
            {:error, "invalid gzip stream: #{inspect(other)}"}
        end
    end
  end

  defp finish_gzip(
         io,
         zlib,
         parser,
         expanded,
         digest,
         compressed_size,
         limits,
         status,
         crc
       ) do
    case :zlib.safeInflate(zlib, <<>>) do
      {:finished, output} ->
        with {:ok, next_parser, next_expanded, next_crc} <-
               feed_inflated(parser, output, expanded, crc, compressed_size, limits),
             :ok <- gzip_trailer(io, next_crc, next_expanded) do
          {:ok, next_parser, next_expanded, final_digest(digest)}
        end

      {:continue, output} when status == :finished and output == [] ->
        with :ok <- gzip_trailer(io, crc, expanded) do
          {:ok, parser, expanded, final_digest(digest)}
        end

      {:continue, _} ->
        {:error, "gzip stream ended before its final record"}

      other ->
        {:error, "invalid gzip stream: #{inspect(other)}"}
    end
  end

  defp feed_inflated(parser, output, expanded, crc, compressed_size, limits) do
    output
    |> List.wrap()
    |> Enum.reduce_while({:ok, parser, expanded, crc}, fn chunk, {:ok, state, count, checksum} ->
      bytes = IO.iodata_to_binary(chunk)
      next_count = count + byte_size(bytes)

      with :ok <- expanded_bound(next_count, compressed_size, :gzip, limits),
           {:ok, next_state} <- feed(state, bytes, limits) do
        {:cont, {:ok, next_state, next_count, :erlang.crc32(checksum, bytes)}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp gzip_trailer(io, crc, expanded) do
    with {:ok, _} <- :file.position(io, {:eof, -8}),
         {:ok, <<expected_crc::little-32, expected_size::little-32>>} <- :file.read(io, 8) do
      actual_size = band(expanded, 0xFFFFFFFF)

      cond do
        expected_crc != crc ->
          {:error, "gzip trailer CRC mismatch"}

        expected_size != actual_size ->
          {:error, "gzip trailer size mismatch"}

        true ->
          :ok
      end
    else
      _ -> {:error, "gzip stream has no complete trailer"}
    end
  end

  defp feed(%Parser{phase: :header} = parser, bytes, limits) do
    combined = parser.buffer <> bytes

    if byte_size(combined) < @block_size do
      {:ok, %{parser | buffer: combined}}
    else
      <<header::binary-size(@block_size), rest::binary>> = combined
      parser = %{parser | buffer: <<>>}

      cond do
        zero_block?(header) and parser.zero_blocks == 0 ->
          feed(%{parser | zero_blocks: 1}, rest, limits)

        zero_block?(header) and parser.zero_blocks == 1 ->
          feed(%{parser | phase: :end, zero_blocks: 2}, rest, limits)

        parser.zero_blocks > 0 ->
          {:error, "archive contains an entry after its end marker"}

        true ->
          with {:ok, current} <- parse_header(header, parser, limits),
               {:ok, next} <- start_entry(parser, current, limits) do
            feed(next, rest, limits)
          end
      end
    end
  end

  defp feed(%Parser{phase: :data, remaining: remaining} = parser, bytes, limits) do
    take = min(remaining, byte_size(bytes))
    <<content::binary-size(^take), rest::binary>> = bytes
    current = update_current(parser.current, content)
    parser = %{parser | current: current, remaining: remaining - take}

    if parser.remaining == 0 do
      with {:ok, next} <- finish_entry(parser) do
        feed(next, rest, limits)
      end
    else
      {:ok, parser}
    end
  end

  defp feed(%Parser{phase: :padding, padding: padding} = parser, bytes, limits) do
    take = min(padding, byte_size(bytes))
    <<padding_bytes::binary-size(^take), rest::binary>> = bytes

    if zero_block?(padding_bytes) do
      next_padding = padding - take

      next = %{
        parser
        | padding: next_padding,
          phase: if(next_padding == 0, do: :header, else: :padding)
      }

      feed(next, rest, limits)
    else
      {:error, "archive entry padding contains nonzero bytes"}
    end
  end

  defp feed(%Parser{phase: :end} = parser, bytes, _) do
    if zero_block?(bytes),
      do: {:ok, parser},
      else: {:error, "archive has data after its end marker"}
  end

  defp start_entry(parser, current, limits) do
    cond do
      parser.entry_count >= limits.entries ->
        {:error, "archive exceeds #{limits.entries} entries"}

      MapSet.member?(parser.paths, current.path) ->
        {:error, "archive repeats normalized path #{inspect(current.path)}"}

      current.size > limits.file_bytes ->
        {:error, "#{current.path}: file exceeds #{limits.file_bytes} bytes"}

      current.path == @manifest_path and current.size > limits.manifest_bytes ->
        {:error, "payload manifest exceeds #{limits.manifest_bytes} bytes"}

      true ->
        current =
          Map.merge(current, %{
            hash: :crypto.hash_init(:sha256),
            captured: if(current.path == @manifest_path, do: [], else: nil)
          })

        parser = %{
          parser
          | current: current,
            remaining: current.size,
            paths: MapSet.put(parser.paths, current.path),
            entry_count: parser.entry_count + 1,
            phase: :data
        }

        if current.size == 0, do: finish_entry(parser), else: {:ok, parser}
    end
  end

  defp update_current(current, <<>>), do: current

  defp update_current(current, bytes) do
    captured = if is_list(current.captured), do: [bytes | current.captured], else: nil
    %{current | hash: :crypto.hash_update(current.hash, bytes), captured: captured}
  end

  defp finish_entry(parser) do
    current = parser.current
    raw_digest = :crypto.hash_final(current.hash)
    digest = Base.encode16(raw_digest, case: :lower)

    entry = %{
      "path" => current.path,
      "kind" => current.kind,
      "mode" => current.mode,
      "size" => current.size,
      "sha256" => if(current.kind == "file", do: digest, else: nil),
      "link_target" => current.link_target
    }

    manifest_bytes =
      if current.path == @manifest_path do
        captured = Enum.reverse(current.captured)
        IO.iodata_to_binary(captured)
      else
        parser.manifest_bytes
      end

    padding = rem(@block_size - rem(current.size, @block_size), @block_size)

    {:ok,
     %{
       parser
       | current: nil,
         remaining: 0,
         padding: padding,
         phase: if(padding == 0, do: :header, else: :padding),
         entries:
           if(current.path == @manifest_path, do: parser.entries, else: [entry | parser.entries]),
         manifest_bytes: manifest_bytes
     }}
  end

  defp parse_header(header, parser, limits) do
    with :ok <- checksum(header),
         {:ok, name} <- string_field(binary_part(header, 0, 100), "name"),
         {:ok, prefix} <- string_field(binary_part(header, 345, 155), "prefix"),
         {:ok, path} <- header_path(prefix, name),
         :ok <- path_bounds(path, limits),
         :ok <- PayloadManifest.validate_path(path),
         {:ok, mode} <- octal(binary_part(header, 100, 8), "mode"),
         {:ok, size} <- octal(binary_part(header, 124, 12), "size"),
         {:ok, kind, link_target} <-
           entry_kind(:binary.at(header, 156), binary_part(header, 157, 100), path),
         :ok <- safe_mode(path, mode, kind),
         :ok <- kind_size(kind, size, path),
         :ok <- manifest_uniqueness(path, parser) do
      {:ok,
       %{
         path: path,
         kind: kind,
         mode: band(mode, 0o777),
         size: size,
         link_target: link_target
       }}
    end
  end

  defp entry_kind(type, _, _) when type in [0, ?0], do: {:ok, "file", nil}
  defp entry_kind(?5, _, _), do: {:ok, "directory", nil}

  defp entry_kind(?2, link_field, path) do
    with {:ok, target} <- string_field(link_field, "link target"),
         {:ok, normalized} <- PayloadManifest.normalize_link_target(path, target) do
      {:ok, "symlink", normalized}
    end
  end

  defp entry_kind(?1, link_field, path) do
    with {:ok, target} <- string_field(link_field, "hard-link target"),
         {:ok, _} <- PayloadManifest.normalize_link_target(path, target) do
      {:error, "#{path}: hard links are not admitted by this artifact format"}
    end
  end

  defp entry_kind(type, _, path) when type in [?3, ?4, ?6],
    do: {:error, "#{path}: device nodes and FIFOs are forbidden"}

  defp entry_kind(type, _, path),
    do: {:error, "#{path}: tar entry type #{inspect(<<type>>)} is unsupported"}

  defp kind_size("file", _, _), do: :ok
  defp kind_size(_, 0, _), do: :ok
  defp kind_size(_, _, path), do: {:error, "#{path}: non-file entry has content bytes"}

  defp manifest_uniqueness(@manifest_path, %Parser{manifest_bytes: nil}), do: :ok
  defp manifest_uniqueness(@manifest_path, _), do: {:error, "archive repeats its payload manifest"}
  defp manifest_uniqueness(_, _), do: :ok

  defp finish(%Parser{phase: :end, manifest_bytes: nil}),
    do: {:error, "archive does not contain #{@manifest_path}"}

  defp finish(%Parser{phase: :end} = parser),
    do: {:ok, Enum.sort_by(parser.entries, & &1["path"]), parser.manifest_bytes}

  defp finish(%Parser{phase: phase}), do: {:error, "archive ended during #{phase}"}

  defp checksum(header) do
    with {:ok, expected} <- octal(binary_part(header, 148, 8), "checksum") do
      <<before::binary-size(148), _::binary-size(8), after_checksum::binary>> = header
      checksum_bytes = before <> String.duplicate(" ", 8) <> after_checksum
      actual = Enum.sum(:binary.bin_to_list(checksum_bytes))

      if actual == expected,
        do: :ok,
        else: {:error, "tar header checksum mismatch: expected #{expected}, computed #{actual}"}
    end
  end

  defp octal(field, name) do
    trimmed =
      field
      |> :binary.bin_to_list()
      |> Enum.drop_while(&(&1 in [0, 32]))
      |> Enum.reverse()
      |> Enum.drop_while(&(&1 in [0, 32]))
      |> Enum.reverse()
      |> :erlang.list_to_binary()

    cond do
      trimmed == "" -> {:ok, 0}
      not String.match?(trimmed, ~r/^[0-7]+$/) -> {:error, "tar #{name} is not portable octal"}
      true -> {:ok, String.to_integer(trimmed, 8)}
    end
  end

  defp string_field(field, name) do
    case :binary.match(field, <<0>>) do
      :nomatch ->
        valid_string(field, name)

      {index, 1} ->
        value = binary_part(field, 0, index)
        padding = binary_part(field, index, byte_size(field) - index)

        if zero_block?(padding),
          do: valid_string(value, name),
          else: {:error, "tar #{name} contains bytes after its terminator"}
    end
  end

  defp valid_string(value, name) do
    if String.valid?(value) and not String.contains?(value, <<0>>),
      do: {:ok, value},
      else: {:error, "tar #{name} is not valid UTF-8"}
  end

  defp header_path("", name), do: {:ok, name}
  defp header_path(prefix, name), do: {:ok, prefix <> "/" <> name}

  defp path_bounds(path, limits) do
    cond do
      byte_size(path) > limits.path_bytes ->
        {:error, "archive path exceeds #{limits.path_bytes} bytes"}

      length(String.split(path, "/", trim: false)) > limits.path_depth ->
        {:error, "archive path exceeds nesting depth #{limits.path_depth}"}

      true ->
        :ok
    end
  end

  defp safe_mode(_, _, "symlink"), do: :ok

  defp safe_mode(path, mode, _) do
    cond do
      band(mode, 0o6000) != 0 -> {:error, "#{path}: set-user-ID or set-group-ID mode is forbidden"}
      band(mode, 0o002) != 0 -> {:error, "#{path}: world-writable mode is forbidden"}
      true -> :ok
    end
  end

  defp ordinary_file(path) do
    if not is_binary(path) or Path.type(path) != :absolute do
      {:error, "artifact archive path must be absolute"}
    else
      case File.lstat(path) do
        {:ok, %{type: :regular} = stat} -> {:ok, stat}
        {:ok, %{type: type}} -> {:error, "artifact archive must be a regular file, got #{type}"}
        {:error, reason} -> {:error, "artifact archive: #{:file.format_error(reason)}"}
      end
    end
  end

  defp encoding(path) do
    case :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
      {:ok, io} ->
        result =
          case :file.pread(io, 0, 2) do
            {:ok, <<0x1F, 0x8B>>} -> {:ok, :gzip}
            {:ok, _} -> {:ok, :tar}
            :eof -> {:error, "artifact archive is empty"}
            {:error, reason} -> {:error, "artifact archive: #{:file.format_error(reason)}"}
          end

        :file.close(io)
        result

      {:error, reason} ->
        {:error, "artifact archive: #{:file.format_error(reason)}"}
    end
  end

  defp compressed_bound(size, limits) do
    if size <= limits.compressed_bytes,
      do: :ok,
      else: {:error, "archive exceeds #{limits.compressed_bytes} compressed bytes"}
  end

  defp expanded_bound(size, compressed_size, encoding, limits) do
    cond do
      size > limits.expanded_bytes ->
        {:error, "archive exceeds #{limits.expanded_bytes} expanded bytes"}

      encoding == :gzip and size > compressed_size * limits.expansion_ratio ->
        {:error, "archive exceeds expansion ratio #{limits.expansion_ratio}:1"}

      true ->
        :ok
    end
  end

  defp zero_block?(bytes), do: bytes == <<0::size(byte_size(bytes) * 8)>>

  defp final_digest(context) do
    digest = :crypto.hash_final(context)
    Base.encode16(digest, case: :lower)
  end

  defp safe_inflate_end(zlib) do
    :zlib.inflateEnd(zlib)
  catch
    :error, _ -> :ok
  end
end
