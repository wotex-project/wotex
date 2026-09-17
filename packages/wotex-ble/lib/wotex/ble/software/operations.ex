defmodule Wotex.BLE.Software.Operations do
  @moduledoc false

  alias Wotex.BLE.Native.{Bootstrap, BuildOperations, Command, Source}

  @doc false
  @spec find_executable(String.t()) :: String.t() | nil
  def find_executable(name), do: System.find_executable(name)

  @doc false
  @spec tool_digest(String.t()) :: {:ok, String.t()} | {:error, :invalid_native_tool}
  def tool_digest(path), do: BuildOperations.tool_digest(path)

  @doc false
  @spec bootstrap(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Bootstrap.result()} | {:error, atom(), Bootstrap.result()}
  def bootstrap(compiler, source, output, directory),
    do: Bootstrap.compile(compiler, source, output, directory)

  @doc false
  @spec command(String.t(), Command.step()) ::
          {:ok, Command.result()} | {:error, atom(), Command.result()}
  def command(guardian, step), do: Command.run(guardian, step)

  @doc false
  @spec transfer(String.t(), String.t(), String.t()) :: :ok | {:error, Source.download_error()}
  def transfer(url, target, sha256),
    do:
      Source.transfer(url, target, sha256,
        cacerts: :public_key.cacerts_get(),
        bytes: 33_554_432
      )

  @doc false
  @spec digest(String.t()) :: {:ok, String.t()} | {:error, :invalid_source_file}
  def digest(path), do: Source.digest(path)
end
