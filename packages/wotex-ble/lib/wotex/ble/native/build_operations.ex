defmodule Wotex.BLE.Native.BuildOperations do
  @moduledoc false

  alias Wotex.BLE.Native.{Bootstrap, Command, Source}

  @maximum_tool 536_870_912

  @doc false
  @spec platform() :: {:ok, String.t()} | {:error, :linux_required}
  def platform do
    if :os.type() == {:unix, :linux},
      do: {:ok, List.to_string(:erlang.system_info(:system_architecture))},
      else: {:error, :linux_required}
  end

  @doc false
  @spec find_executable(String.t()) :: String.t() | nil
  def find_executable(name), do: System.find_executable(name)

  @doc false
  @spec tool_digest(String.t()) :: {:ok, String.t()} | {:error, :invalid_native_tool}
  def tool_digest(path) do
    with {:ok, %File.Stat{type: :regular, size: size}} when size <= @maximum_tool <- File.stat(path),
         {:ok, bytes} <- File.read(path) do
      {:ok, Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}
    else
      _ -> {:error, :invalid_native_tool}
    end
  end

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
  @spec fetch(Source.pin(), String.t()) :: :ok | {:error, atom()}
  def fetch(pin, target), do: Source.fetch(pin, target)

  @doc false
  @spec extract(String.t(), String.t(), String.t()) :: :ok | {:error, atom()}
  def extract(archive, destination, root), do: Source.extract(archive, destination, root)
end
