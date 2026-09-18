defmodule Wotex.Lab.Check.WorkDirectory do
  @moduledoc false

  @prefixes %{
    package: ".archive-check.",
    archive_consumer: ".archive-check.consumer-",
    workbench_archive: ".archive-check.workbench-",
    reference: ".archive-check.reference-"
  }

  @spec create!(Path.t(), :package | :archive_consumer | :workbench_archive | :reference) ::
          Path.t()
  def create!(root, kind) do
    root = Path.expand(root)
    prefix = Map.fetch!(@prefixes, kind)
    suffix = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    path = Path.join(root, prefix <> suffix)
    # mkdir is exclusive. Even an unlikely collision must fail, never merge
    # old extracted content with this attempt or erase earlier evidence.
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    path
  end
end
