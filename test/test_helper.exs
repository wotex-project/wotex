defmodule WotexWorkspace.Fixtures do
  @moduledoc false

  alias Wotex.Workspace.Manifest

  @manifest %{
    "schema_version" => "1.0.0",
    "lanes" => %{
      "minimum" => %{"elixir" => "1.18.4-otp-27", "otp" => "27.3.4.15"},
      "current" => %{"elixir" => "1.20.2-otp-29", "otp" => "29.0.4"}
    },
    "select_all_on" => [".github/**", "tooling/**", ".tool-versions", "mix.exs", "lib/**"],
    "packages" => %{
      "core" => %{"app" => "core", "depends_on" => []},
      "runtime" => %{"app" => "runtime", "depends_on" => ["core"]},
      "http" => %{"app" => "http", "depends_on" => ["core", "runtime"]},
      "coap" => %{
        "app" => "coap",
        "depends_on" => ["core", "runtime"],
        "native" => true,
        "native_task" => "coap.native.build",
        "software_task" => "coap.software.run"
      },
      "conformance" => %{"app" => "conformance", "depends_on" => []},
      "lab" => %{
        "app" => "lab",
        "depends_on" => ["core", "http", "conformance"],
        "native" => true
      }
    }
  }

  @doc "The fixture manifest as a decoded YAML map."
  @spec manifest_map() :: map()
  def manifest_map, do: @manifest

  @doc "The fixture manifest, validated."
  @spec manifest() :: Manifest.t()
  def manifest do
    {:ok, manifest} = Manifest.from_map(@manifest, "fixture.yaml")
    manifest
  end

  @doc "A fresh temporary directory, removed when the test exits."
  @spec tmp_dir(map() | String.t() | atom()) :: Path.t()
  def tmp_dir(context_or_name) do
    name =
      case context_or_name do
        %{test: test} -> String.replace(Atom.to_string(test), ~r/[^a-z0-9]+/i, "-")
        name -> to_string(name)
      end

    path =
      Path.join([
        System.tmp_dir!(),
        "wotex-workspace-test",
        "#{name}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(path)
    File.mkdir_p!(path)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  @doc "Writes `content` at `relative` below `root`, creating directories."
  @spec write!(Path.t(), Path.t(), iodata()) :: Path.t()
  def write!(root, relative, content) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end
end

ExUnit.start()
