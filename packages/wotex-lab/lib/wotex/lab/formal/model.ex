defmodule Wotex.Lab.Formal.Model do
  @moduledoc """
  The checked-in, digest-addressed finite control models.

  `priv/models/manifest.json` names every model with its file, SHA-256 digest,
  engine, license, module names and bounds. `fetch/1` reads the manifest for a
  known model id and `verify/1` compares the file on disk with the recorded
  digest, so a profile can only run a model whose bytes match what the
  catalogue describes. Nothing here starts a process or reads the network.

  `ids/0` and `variants/0` expose closed catalogue vocabularies. Verification
  establishes content identity only; engine availability, execution bounds,
  model interpretation, and the resulting evidence remain responsibilities of
  the formal profile and its consumer-owned port.
  """

  alias Wotex.JSON
  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Digest

  @ids %{thermal_control_v1: "thermal-control-v1"}
  @variants ~w(safe broken_duplicate broken_stale broken_energy broken_both broken_ungranted)a

  @type variant ::
          :safe
          | :broken_duplicate
          | :broken_stale
          | :broken_energy
          | :broken_both
          | :broken_ungranted

  @type t :: %{
          id: atom(),
          name: String.t(),
          path: Path.t(),
          digest: String.t(),
          engine: String.t(),
          license: String.t(),
          modules: %{variant() => String.t()},
          bounds: %{max_age: pos_integer(), max_grants: pos_integer()}
        }

  @doc "Known model ids."
  @spec ids() :: [atom()]
  def ids, do: Map.keys(@ids)

  @doc "Model variants: the safe policy and each deliberately broken module."
  @spec variants() :: [variant()]
  def variants, do: @variants

  @doc "Reads one model's manifest entry."
  @spec fetch(atom()) :: {:ok, t()} | {:error, Error.t()}
  def fetch(id) when is_map_key(@ids, id) do
    name = Map.fetch!(@ids, id)

    with {:ok, manifest} <- manifest(),
         {:ok, entry} <- entry(manifest, name) do
      {:ok,
       %{
         id: id,
         name: name,
         path: Path.join(models_dir(), entry["file"]),
         digest: entry["digest"],
         engine: entry["engine"],
         license: entry["license"],
         modules:
           Map.merge(
             %{safe: entry["safe_module"]},
             Map.new(@variants -- [:safe], &{&1, entry["broken_modules"][Atom.to_string(&1)]})
           ),
         bounds: %{max_age: entry["bounds"]["max_age"], max_grants: entry["bounds"]["max_grants"]}
       }}
    end
  end

  def fetch(id),
    do:
      {:error, Error.new(:unknown_model, :admission, "model is not catalogued", details: %{id: id})}

  @doc "Verifies the model file on disk against its recorded digest."
  @spec verify(t()) :: {:ok, t()} | {:error, Error.t()}
  def verify(%{path: path, digest: digest} = model) do
    case Digest.file(path) do
      {:ok, ^digest} ->
        {:ok, model}

      {:ok, actual} ->
        {:error,
         Error.new(
           :model_digest_mismatch,
           :admission,
           "model file does not match its manifest digest",
           details: %{expected: digest, actual: actual}
         )}

      {:error, reason} ->
        {:error,
         Error.new(:model_unreadable, :admission, "model file cannot be read",
           details: %{reason: reason}
         )}
    end
  end

  defp models_dir, do: Application.app_dir(:wotex_lab, "priv/models")

  defp manifest do
    with {:ok, bytes} <- File.read(Path.join(models_dir(), "manifest.json")),
         {:ok, %{"schema_version" => "1.0.0", "models" => models}} when is_list(models) <-
           JSON.decode(bytes, max_bytes: 65_536) do
      {:ok, models}
    else
      _other -> {:error, Error.new(:invalid_manifest, :admission, "model manifest is not readable")}
    end
  end

  defp entry(models, name) do
    case Enum.find(models, &(&1["id"] == name)) do
      %{
        "file" => file,
        "digest" => "sha256:" <> _,
        "safe_module" => safe,
        "broken_modules" => broken,
        "bounds" => bounds
      } = entry
      when is_binary(file) and is_binary(safe) and is_map(broken) and is_map(bounds) ->
        {:ok, entry}

      _other ->
        {:error,
         Error.new(:invalid_manifest, :admission, "model manifest entry is incomplete",
           details: %{id: name}
         )}
    end
  end
end
