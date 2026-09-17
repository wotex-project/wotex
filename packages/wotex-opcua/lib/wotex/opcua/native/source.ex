defmodule Wotex.OPCUA.Native.Source do
  @moduledoc """
  Supplies the reviewed source identities for the explicit native build.

  `fetch/1` returns the SDK or cryptographic library archive identity and its
  required extraction root. The identities are compiled from the packaged
  WOP.13 source manifest; querying them performs no filesystem or network work.
  The build must verify the archive digest before using its contents. A source
  identity does not establish a successful build or admit a runtime capability.

  `manifest_digest/0` identifies the complete reviewed manifest, including its
  SDK reuse and independent-peer boundary. Build reuse additionally requires
  matching toolchain, options, source and executable identities.

  ## Examples

      iex> {:ok, source} = Wotex.OPCUA.Native.Source.fetch(:open62541)
      iex> {source.name, source.version, source.root}
      {"open62541", "1.5.7", "open62541-1.5.7"}
      iex> Wotex.OPCUA.Native.Source.fetch(:ambient)
      {:error, :unsupported_native_source}
  """

  @manifest Path.expand("../../../../priv/fixtures/native-sources-v1.json", __DIR__)
  @external_resource @manifest
  @bytes File.read!(@manifest)
  @digest Base.encode16(:crypto.hash(:sha256, @bytes), case: :lower)
  @sources Jason.decode!(@bytes)["sources"]
  @names %{open62541: "open62541", openssl: "openssl"}
  @roots %{open62541: "open62541-1.5.7", openssl: "openssl-openssl-3.5.8"}

  @typedoc "An exact reviewed archive and its one permitted extraction root."
  @type t :: %{
          name: String.t(),
          version: String.t(),
          commit: String.t(),
          url: String.t(),
          sha256: String.t(),
          root: String.t()
        }

  @doc "Returns one pinned source, rejecting unsupported selectors without I/O."
  @spec fetch(term()) :: {:ok, t()} | {:error, :unsupported_native_source}
  def fetch(name) when name in [:open62541, :openssl] do
    source = Enum.find(@sources, &(&1["name"] == Map.fetch!(@names, name)))

    {:ok,
     %{
       name: source["name"],
       version: source["version"],
       commit: source["commit"],
       url: source["url"],
       sha256: source["sha256"],
       root: Map.fetch!(@roots, name)
     }}
  end

  def fetch(_), do: {:error, :unsupported_native_source}

  @doc "Returns the SHA-256 of the source manifest compiled into this package."
  @spec manifest_digest() :: String.t()
  def manifest_digest, do: @digest
end
