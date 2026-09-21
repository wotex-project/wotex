defmodule WotexWorkspace.NativeArtifactArchiveFixture do
  @moduledoc false

  import Bitwise

  @block 512

  @spec write!(Path.t(), [map()], keyword()) :: Path.t()
  def write!(path, entries, opts \\ []) do
    bytes = bytes(entries, opts)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    path
  end

  @spec bytes([map()], keyword()) :: binary()
  def bytes(entries, opts \\ []) do
    archive =
      entries
      |> Enum.map(&entry/1)
      |> Kernel.++([<<0::size(@block * 8)>>, <<0::size(@block * 8)>>])
      |> IO.iodata_to_binary()

    archive =
      if opts[:truncate],
        do: binary_part(archive, 0, byte_size(archive) - opts[:truncate]),
        else: archive

    if opts[:gzip], do: :zlib.gzip(archive), else: archive
  end

  defp entry(entry) do
    kind = Map.get(entry, :kind, :file)
    content = Map.get(entry, :content, "")
    size = if kind == :file, do: byte_size(content), else: Map.get(entry, :size, 0)
    type = Map.get(entry, :type, type(kind))
    mode = Map.get(entry, :mode, default_mode(kind))
    name = Map.fetch!(entry, :path)
    link = Map.get(entry, :link_target, "")

    header =
      name_field(name, 100) <>
        octal(mode, 8) <>
        octal(0, 8) <>
        octal(0, 8) <>
        octal(size, 12) <>
        octal(0, 12) <>
        String.duplicate(" ", 8) <>
        <<type>> <>
        name_field(link, 100) <>
        "ustar\0" <>
        "00" <>
        zero(32) <>
        zero(32) <>
        octal(0, 8) <>
        octal(0, 8) <>
        zero(155) <>
        zero(12)

    checksum = Enum.sum(:binary.bin_to_list(header))
    <<before::binary-size(148), _::binary-size(8), after_checksum::binary>> = header
    header = before <> checksum_field(checksum) <> after_checksum
    padding = rem(@block - rem(size, @block), @block)
    [header, content, zero(padding)]
  end

  defp name_field(value, width) when byte_size(value) <= width,
    do: value <> zero(width - byte_size(value))

  defp octal(value, width) do
    encoded = Integer.to_string(value, 8)
    String.pad_leading(encoded, width - 1, "0") <> <<0>>
  end

  defp checksum_field(value),
    do: String.pad_leading(Integer.to_string(value, 8), 6, "0") <> <<0, 32>>

  defp type(:file), do: ?0
  defp type(:directory), do: ?5
  defp type(:symlink), do: ?2
  defp type(:hardlink), do: ?1

  defp default_mode(:directory), do: 0o755
  defp default_mode(:symlink), do: 0o777
  defp default_mode(_), do: 0o644

  defp zero(0), do: <<>>
  defp zero(size), do: <<0::size(size * 8)>>

  @spec corrupt_checksum(binary()) :: binary()
  def corrupt_checksum(bytes) do
    <<first, rest::binary>> = bytes
    <<bxor(first, 1), rest::binary>>
  end
end
