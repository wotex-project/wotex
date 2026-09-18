defmodule WotexLabWorkbench.Formal do
  @moduledoc """
  The host's optional ex_maude verification profile.

  The profile exists only when the operator configured `WOTEX_LAB_MAUDE`:
  the binary is digested, the profile is admitted through
  `Wotex.Lab.Formal.Profile.new/1` and its pool is placed under the host's
  Lab instance. Without an engine every verification answers
  `{:error, :unsupported}` and the workbench shows that word; a missing or
  unverifiable engine is never an empty success. Results are model-scoped
  evidence and never authorize anything.
  """

  use GenServer

  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Formal.{Abstraction, Model, Profile, Result, Serializer}

  @pool WotexLabWorkbench.FormalPool
  @properties Map.keys(Serializer.properties())
  @variants Model.variants()

  @doc "Starts the holder with `:lab` and an optional `:engine` path."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The admitted profile or `:unsupported`."
  @spec profile(GenServer.server()) :: {:ok, Profile.t()} | {:error, :unsupported}
  def profile(server \\ __MODULE__), do: GenServer.call(server, :profile)

  @doc "Property ids with descriptions, available even without an engine."
  @spec properties() :: %{atom() => String.t()}
  def properties, do: Serializer.properties()

  @doc "Model variants: the safe policy and each deliberately broken module."
  @spec variants() :: [atom()]
  def variants, do: @variants

  @doc "Admits caller strings to a known property and variant without creating atoms."
  @spec admit(term(), term()) :: {:ok, atom(), atom()} | {:error, Error.t()}
  def admit(property, variant) do
    with {:ok, property} <- known(property, @properties),
         {:ok, variant} <- known(variant, @variants) do
      {:ok, property, variant}
    end
  end

  @doc "Runs one bounded verification from the model's initial abstract room."
  @spec verify(GenServer.server(), atom(), atom()) ::
          {:ok, Result.t()} | {:error, :unsupported | Error.t()}
  def verify(server \\ __MODULE__, property, variant)

  def verify(server, property, variant)
      when property in @properties and variant in @variants do
    case profile(server) do
      {:ok, profile} -> Profile.verify(profile, variant, property, Abstraction.init())
      {:error, :unsupported} -> {:error, :unsupported}
    end
  end

  def verify(_, _, _),
    do: {:error, Error.new(:unknown_selection, :formal, "selection is not in the catalogue")}

  @impl GenServer
  def init(opts) do
    case Keyword.get(opts, :engine) do
      nil ->
        {:ok, %{profile: nil}}

      binary ->
        with {:ok, digest} <- Digest.file(binary),
             {:ok, profile} <- Profile.new(pool: @pool, binary: binary, binary_digest: digest),
             {:ok, _} <-
               Wotex.Lab.start_child(
                 Keyword.fetch!(opts, :lab),
                 :sessions,
                 Profile.child_spec(profile)
               ) do
          {:ok, %{profile: profile}}
        else
          {:error, reason} -> {:stop, {:formal_engine_unusable, reason}}
        end
    end
  end

  @impl GenServer
  def handle_call(:profile, _, %{profile: nil} = state),
    do: {:reply, {:error, :unsupported}, state}

  def handle_call(:profile, _, state), do: {:reply, {:ok, state.profile}, state}

  defp known(value, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> {:error, Error.new(:unknown_selection, :formal, "selection is not in the catalogue")}
      atom -> {:ok, atom}
    end
  end

  defp known(_, _),
    do: {:error, Error.new(:unknown_selection, :formal, "selection is not in the catalogue")}
end
