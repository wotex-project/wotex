defmodule Wotex.Binding.HTTP do
  @moduledoc """
  Caller-owned HTTP and Server-Sent Events binding for Wotex Runtime.

  The package maps selected TD Forms to immutable HTTP values and delegates all
  network activity to a consumer-supplied `Wotex.Binding.HTTP.Client`. It ships
  no client, pool, application callback, supervisor, or credential source.

  The public entry points form one small composition surface:

  * `profile/0` describes the supported schemes, operations, and media type to
    Wotex Runtime.
  * `config/1` validates the client port, static fields, and encoded-byte limits.
  * `transport/1` returns the Runtime transport tuple for that configuration.
  * `empty_body/0` distinguishes an absent Action body from JSON `null`.

  Client callbacks receive credential material separately from immutable HTTP
  requests. See `Wotex.Binding.HTTP.Client` for the request, subscription, and
  close contracts and their lifecycle responsibilities.

  This API implements a documented standards baseline; it does not claim W3C
  WoT Profile conformance or registration in the pilot Binding Registry.
  """

  alias Wotex.Binding.HTTP.{Config, EmptyBody, Error, Transport}
  alias Wotex.Runtime.BindingProfile

  @operations ~w(readproperty writeproperty observeproperty unobserveproperty invokeaction queryaction cancelaction subscribeevent unsubscribeevent)a

  @doc "Builds the HTTP binding profile used by Wotex Runtime Form selection."
  @spec profile() :: {:ok, BindingProfile.t()} | {:error, Wotex.Runtime.Error.t()}
  def profile do
    BindingProfile.new(
      id: :http,
      schemes: ["http", "https"],
      operations: @operations,
      media_types: ["application/json"]
    )
  end

  @doc "Builds validated configuration for a consumer-supplied client."
  @spec config(keyword()) :: {:ok, Config.t()} | {:error, Error.t()}
  def config(opts), do: Config.new(opts)

  @doc "Returns the Runtime transport tuple for validated configuration."
  @spec transport(Config.t()) :: {module(), Config.t()}
  def transport(%Config{} = config), do: {Transport, config}

  @doc "Returns an explicit marker for an operation with no HTTP request body."
  @spec empty_body() :: EmptyBody.t()
  def empty_body, do: EmptyBody.new()
end
