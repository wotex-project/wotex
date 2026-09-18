defmodule Wotex.Workspace do
  @moduledoc """
  Repository-level tooling for the WoTEx package family.

  The root project is not an umbrella and depends on no package under
  `packages/`. It reads `tooling/packages.yaml`, decides which packages a
  change affects and drives each package's own Mix project through
  `Wotex.Workspace.Runner`. Package code never runs inside this VM.
  """

  @root Path.expand("../..", __DIR__)

  @doc """
  Absolute path of the repository root that this project was compiled from.
  """
  @spec root() :: Path.t()
  def root, do: @root

  @doc """
  Makes `path` relative to `root`, or returns it unchanged when it is
  already relative.
  """
  @spec relative(Path.t(), Path.t()) :: Path.t()
  def relative(path, root \\ root()) do
    case Path.type(path) do
      :absolute -> Path.relative_to(path, root)
      _other -> path
    end
  end
end
