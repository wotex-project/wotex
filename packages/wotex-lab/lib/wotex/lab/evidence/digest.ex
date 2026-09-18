defmodule Wotex.Lab.Evidence.Digest do
  @moduledoc """
  Content digests for evidence records, all as `sha256:<hex>`.

  `file/1` digests one file, `tree/2` digests a set of files relative to a
  root as the sorted list of `path\\0digest\\n` lines so the result depends on
  content and relative names only, and `toolchain/1` reports the Elixir, OTP,
  Nx backend and platform strings a record carries. Nothing here reads a
  source revision: a revision alone cannot identify dirty inputs, so records
  carry content digests next to it.
  """

  @doc "Digests one file's bytes."
  @spec file(Path.t()) :: {:ok, String.t()} | {:error, File.posix()}
  def file(path) do
    with {:ok, bytes} <- File.read(path), do: {:ok, bytes(bytes)}
  end

  @doc "Digests one file's bytes, raising on a read failure."
  @spec file!(Path.t()) :: String.t()
  def file!(path), do: bytes(File.read!(path))

  @doc "Digests the files matched by `patterns` under `root`, by relative name and content."
  @spec tree(Path.t(), [String.t()]) :: {:ok, String.t()} | {:error, File.posix()}
  def tree(root, patterns) when is_list(patterns) do
    files =
      patterns
      |> Enum.flat_map(&Path.wildcard(Path.join(root, &1), match_dot: true))
      |> Enum.filter(&File.regular?/1)
      |> Enum.uniq()
      |> Enum.sort()

    hashed =
      Enum.reduce_while(files, {:ok, :crypto.hash_init(:sha256)}, fn file, {:ok, acc} ->
        case File.read(file) do
          {:ok, content} ->
            relative = Path.relative_to(file, root)
            line = relative <> <<0>> <> bytes(content) <> "\n"
            {:cont, {:ok, :crypto.hash_update(acc, line)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case hashed do
      {:ok, acc} -> {:ok, "sha256:" <> Base.encode16(:crypto.hash_final(acc), case: :lower)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Digests bytes already in memory."
  @spec bytes(binary()) :: String.t()
  def bytes(binary) when is_binary(binary),
    do: "sha256:" <> (:crypto.hash(:sha256, binary) |> Base.encode16(case: :lower))

  @doc "The toolchain strings a record carries for the given Nx backend."
  @spec toolchain(module()) :: %{
          elixir: String.t(),
          otp: String.t(),
          backend: String.t(),
          platform: String.t()
        }
  def toolchain(backend) when is_atom(backend) do
    %{
      elixir: System.version(),
      otp: List.to_string(:erlang.system_info(:otp_release)),
      backend: inspect(backend),
      platform: List.to_string(:erlang.system_info(:system_architecture))
    }
  end
end
