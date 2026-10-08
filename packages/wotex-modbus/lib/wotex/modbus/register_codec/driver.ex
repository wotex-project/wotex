defmodule Wotex.Modbus.RegisterCodec.Driver do
  @moduledoc """
  Consumer-owned custody and execution port for a register process codec.

  Start one driver actor per `Wotex.Modbus.RegisterCodec.Host`. Supply the
  installed artifact, exact loader closure and qualified enforcement explicitly.
  Profile declarations and scripted drivers do not prove native enforcement.
  Every callback must return promptly; opening and cleanup complete by messages.

  Before acquiring resources, `c:open/6` atomically claims an unused actor and
  monitors both host and consumer owner. Custody must survive forced host death,
  bound memory and output, deny privileges and reap escaped descendants. Never
  clean another channel's resources. Loading this behaviour starts nothing.

  Send `{:wotex_modbus_codec, channel, event}` to the host. Events are `:opened`,
  `{:stdout, binary}`, `{:stderr, binary}`, `:exited`, `{:failed, code}` and
  `{:closed, :confirmed_local | :unconfirmed}`. Opened precedes stdout; confirmed
  close requires actual resource and descendant release within the one budget.
  Raw stderr and foreign failure text must never be logged or rendered.
  """

  alias Wotex.Runtime.Implementation.Plan

  @typedoc "Closed failure vocabulary; callbacks never return foreign diagnostic text."
  @type failure ::
          :artifact_unverified
          | :enforcement_unavailable
          | :startup_failed
          | :codec_unavailable
          | :overloaded
          | :cleanup_unconfirmed
  @typedoc "Exact admitted references and the independently owned local driver actor."
  @type profile :: %{
          pid: pid(),
          artifact: map(),
          enforcement: map(),
          codec_contract: map()
        }
  @typedoc "Effective string-keyed C03 ceilings, including one active and zero queued calls."
  @type limits :: %{required(String.t()) => non_neg_integer()}

  @doc "Pure declaration of the already-started actor and exact deployment/enforcement."
  @callback profile(term()) :: {:ok, profile()} | {:error, :enforcement_unavailable}
  @doc "Claims custody, reverifies immutable deployment and asynchronously opens this channel."
  @callback open(pid(), pid(), reference(), Plan.t(), limits(), term()) ::
              :ok | {:error, failure()}
  @doc "Submits bounded bytes for this channel without blocking, retry or replacement."
  @callback write(reference(), binary(), term()) :: :ok | {:error, failure()}
  @doc "Begins one bounded cleanup, reporting actual confirmation asynchronously."
  @callback close(reference(), pos_integer(), term()) :: :ok | {:error, failure()}
end
