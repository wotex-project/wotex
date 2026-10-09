defmodule Wotex.Matter.BridgeProcessFixture do
  @moduledoc false

  alias Wotex.Matter.BridgeWireFixture

  @revision "250a9e6c50ee2068107f3c4808b680f5f2925415"
  @model "dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671"

  @spec directory() :: String.t()
  def directory do
    path = Path.join(System.tmp_dir!(), "wotex-bridge-port-#{System.unique_integer([:positive])}")
    File.mkdir!(path)
    path
  end

  @spec create(String.t(), keyword()) :: String.t()
  def create(directory, sections \\ []) do
    path = Path.join(directory, "host")

    body = """
    #!/bin/sh
    set -eu
    marker=$1
    printf '%s\\n' "$$" > "$marker/pid"
    printf '%s\\n' "${WOTEX_BRIDGE_PRIVATE_CANARY-unset}" > "$marker/environment"
    IFS= read -r line
    generation=${line#*\\"generation\\":\\"}
    generation=${generation%%\\"*}
    #{Keyword.get(sections, :before_ready, "")}
    #{Keyword.get(sections, :ready, ready())}
    IFS= read -r line
    probe=${line#*\\"id\\":\\"}
    probe=${probe%%\\"*}
    #{Keyword.get(sections, :before_sample, "")}
    #{Keyword.get(sections, :sample, sample(100))}
    #{Keyword.get(sections, :after_sample, "")}
    while IFS= read -r line; do
      printf '%s\\n' "$line" >> "$marker/input"
      case "$line" in
        *\\"type\\":\\"clock-probe\\"*)
          probe=${line#*\\"id\\":\\"}
          probe=${probe%%\\"*}
          #{Keyword.get(sections, :next_sample, sample(200))}
          ;;
        *\\"type\\":\\"close\\"*)
          #{Keyword.get(sections, :closing, closed())}
          exit 0
          ;;
        *\\"type\\":\\"result\\"*)
          #{Keyword.get(sections, :after_result, "")}
          ;;
      esac
    done
    """

    File.write!(path, body)
    File.chmod!(path, 0o700)
    path
  end

  @spec ready() :: String.t()
  def ready do
    printf(%{
      "v" => 1,
      "backend" => "matter-bridge",
      "type" => "ready",
      "generation" => "$generation",
      "sdk_revision" => @revision,
      "model_sha256" => @model
    })
  end

  @spec sample(non_neg_integer(), String.t()) :: String.t()
  def sample(native, id \\ "$probe") do
    printf(%{
      "v" => 1,
      "backend" => "matter-bridge",
      "type" => "clock-sample",
      "generation" => "$generation",
      "id" => id,
      "native_ms" => Integer.to_string(native)
    })
  end

  @spec closed() :: String.t()
  def closed do
    printf(%{
      "v" => 1,
      "backend" => "matter-bridge",
      "type" => "closed",
      "generation" => "$generation"
    })
  end

  @spec request(String.t(), pos_integer(), pos_integer(), map()) :: String.t()
  def request(operation, id, deadline, changes \\ %{}) do
    BridgeWireFixture.frame(operation)
    |> Map.merge(%{
      "generation" => "$generation",
      "id" => Integer.to_string(id),
      "deadline_ms" => Integer.to_string(deadline)
    })
    |> Map.merge(changes)
    |> printf()
  end

  @spec printf(map()) :: String.t()
  def printf(frame) do
    bytes = Jason.encode!(frame)
    # Only fixture-generated generation/probe variables expand. Opaque frame
    # content stays shell-quoted; no user input is evaluated by a shell.
    quoted = String.replace(bytes, "'", "'\\''")
    quoted = String.replace(quoted, "$generation", "'\"$generation\"'")
    quoted = String.replace(quoted, "$probe", "'\"$probe\"'")
    "printf '%s\\n' '#{quoted}'"
  end

  @spec digest(String.t()) :: String.t()
  def digest(executable),
    do: :crypto.hash(:sha256, File.read!(executable)) |> Base.encode16(case: :lower)

  @spec input(String.t()) :: [map()]
  def input(directory) do
    case File.read(Path.join(directory, "input")) do
      {:ok, bytes} ->
        bytes
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      _ ->
        []
    end
  end
end
