defmodule Wotex.Lab.Island.Snapshot do
  @moduledoc "A bounded full-state envelope for one Wotex Lab island."

  alias Wotex.Lab.Island.{CanonicalJSON, Component, Encoder}

  @schema "wotex-lab-island/v1"
  @max_snapshot_bytes 512 * 1_024
  @max_inline_bytes 32 * 1_024
  @max_patch_bytes 128 * 1_024
  @max_patch_operations 256

  @enforce_keys [
    :schema,
    :component,
    :instance_id,
    :generation,
    :revision,
    :payload_digest,
    :payload,
    :capabilities
  ]
  defstruct @enforce_keys

  @typedoc "A validated island snapshot with decimal-string generation and revision."
  @type t :: %__MODULE__{
          schema: String.t(),
          component: String.t(),
          instance_id: String.t(),
          generation: String.t(),
          revision: String.t(),
          payload_digest: String.t(),
          payload: map(),
          capabilities: [String.t()]
        }

  @doc "Builds and sizes a full snapshot for one admitted component."
  @spec new(String.t(), String.t(), map() | keyword(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(component, instance_id, props, opts \\ []) do
    generation = Keyword.get(opts, :generation, "0")
    revision = Keyword.get(opts, :revision, "0")
    capabilities = Keyword.get(opts, :capabilities, [])

    with :ok <- validate_options(opts),
         true <- valid_id?(instance_id),
         true <- decimal?(generation) and decimal?(revision),
         true <- valid_capabilities?(capabilities),
         {:ok, payload} <- Encoder.encode(component, props),
         {:ok, digest} <- CanonicalJSON.digest(payload),
         snapshot = %__MODULE__{
           schema: @schema,
           component: component,
           instance_id: instance_id,
           generation: generation,
           revision: revision,
           payload_digest: digest,
           payload: payload,
           capabilities: capabilities
         },
         {:ok, bytes} <- encode(snapshot),
         true <- byte_size(bytes) <= @max_snapshot_bytes do
      {:ok, snapshot}
    else
      false -> {:error, :invalid_island_snapshot_identity}
      {:error, _} = error -> error
    end
  end

  @doc "Encodes a snapshot to canonical protocol bytes."
  @spec encode(t()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = snapshot) do
    snapshot
    |> Map.from_struct()
    |> stringify_keys()
    |> CanonicalJSON.encode()
  end

  def encode(_), do: {:error, :invalid_island_snapshot}

  @doc "Encodes an inline snapshot as unpadded URL-safe base64 within 32 KiB."
  @spec encode_inline(t()) :: {:ok, String.t()} | {:error, term()}
  def encode_inline(%__MODULE__{} = snapshot) do
    with {:ok, bytes} <- encode(snapshot),
         true <- byte_size(bytes) <= @max_inline_bytes do
      {:ok, Base.url_encode64(bytes, padding: false)}
    else
      false -> {:error, {:island_limit, :inline_snapshot_bytes, :exceeded, @max_inline_bytes}}
      {:error, _} = error -> error
    end
  end

  def encode_inline(_), do: {:error, :invalid_island_snapshot}

  @doc "Builds a closed add/remove/replace patch for an admitted next payload."
  @spec patch(t(), map() | keyword(), String.t(), [map()]) :: {:ok, map()} | {:error, term()}
  def patch(%__MODULE__{} = snapshot, next_props, revision, operations) do
    with true <- decimal?(revision),
         true <- is_list(operations) and length(operations) <= @max_patch_operations,
         :ok <- validate_operations(operations, snapshot.component),
         {:ok, payload} <- Encoder.encode(snapshot.component, next_props),
         {:ok, digest} <- CanonicalJSON.digest(payload),
         patch = %{
           "schema" => @schema,
           "component" => snapshot.component,
           "instance_id" => snapshot.instance_id,
           "generation" => snapshot.generation,
           "revision" => revision,
           "base_revision" => snapshot.revision,
           "payload_digest" => digest,
           "operations" => operations,
           "capabilities" => snapshot.capabilities
         },
         {:ok, bytes} <- CanonicalJSON.encode(patch),
         true <- byte_size(bytes) <= @max_patch_bytes do
      {:ok, patch}
    else
      false -> {:error, :invalid_island_patch}
      {:error, _} = error -> error
    end
  end

  def patch(_, _, _, _), do: {:error, :invalid_island_patch}

  defp validate_options(opts) do
    if Keyword.keyword?(opts) and
         Keyword.keys(opts) -- [:generation, :revision, :capabilities] == [],
       do: :ok,
       else: {:error, :invalid_island_snapshot_options}
  end

  defp valid_id?(value),
    do: is_binary(value) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9._:-]*\z/, value)

  defp decimal?(value), do: is_binary(value) and Regex.match?(~r/\A(?:0|[1-9][0-9]*)\z/, value)

  defp valid_capabilities?(values),
    do: is_list(values) and values == Enum.uniq(values) and Enum.all?(values, &valid_id?/1)

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp validate_operations(operations, component) do
    with {:ok, descriptor} <- Component.fetch(component) do
      allowed = Map.keys(descriptor["props"])

      if Enum.all?(operations, &valid_operation?(&1, allowed)),
        do: :ok,
        else: {:error, :invalid_island_patch_operation}
    end
  end

  defp valid_operation?(%{"op" => operation, "path" => "/" <> path} = value, allowed)
       when operation in ["add", "remove", "replace"] do
    [field | segments] = String.split(path, "/")

    field in allowed and
      Enum.all?([field | segments], &(&1 not in ["", "__proto__", "prototype", "constructor"])) and
      (operation == "remove" or Map.has_key?(value, "value"))
  end

  defp valid_operation?(_, _), do: false
end
