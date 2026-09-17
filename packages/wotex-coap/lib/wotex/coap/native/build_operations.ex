defmodule Wotex.CoAP.Native.BuildOperations do
  @moduledoc false

  alias Wotex.CoAP.Native.{Archive, BuildCommand, Toolchain, Workspace}

  @doc false
  @spec resolve() :: {:ok, Toolchain.t()} | {:error, term()}
  def resolve, do: Toolchain.resolve()

  @doc false
  @spec identify(map(), String.t(), term()) :: {:ok, Toolchain.t()} | {:error, term()}
  def identify(paths, openssl_root, target),
    do: Toolchain.identify(paths, openssl_root, target)

  @doc false
  @spec direct(String.t(), [String.t()], String.t(), keyword()) ::
          {:ok, BuildCommand.result()} | {:error, atom(), BuildCommand.result()}
  def direct(executable, arguments, cwd, options),
    do: BuildCommand.direct(executable, arguments, cwd, options)

  @doc false
  @spec command(String.t(), String.t(), [String.t()], String.t(), keyword()) ::
          {:ok, BuildCommand.result()} | {:error, atom(), BuildCommand.result()}
  def command(guardian, executable, arguments, cwd, options),
    do: BuildCommand.run(guardian, executable, arguments, cwd, options)

  @doc false
  @spec extract(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def extract(archive, destination, source), do: Archive.extract(archive, destination, source)

  @doc false
  @spec digest(String.t()) :: {:ok, String.t()} | {:error, term()}
  def digest(path), do: Workspace.digest(path)

  @doc false
  @spec runtime(String.t()) :: {:ok, %{path: String.t(), sha256: String.t()}} | {:error, term()}
  def runtime(name) do
    with {:ok, path} <- Toolchain.executable(name),
         {:ok, digest} <- Workspace.digest(path),
         do: {:ok, %{path: path, sha256: digest}}
  end
end
