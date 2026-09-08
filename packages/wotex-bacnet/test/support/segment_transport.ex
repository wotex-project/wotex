defmodule Wotex.BACnet.Test.SegmentTransport do
  @moduledoc false

  @spec is_valid_destination(term()) :: true
  # Required SDK callback spelling.
  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_valid_destination(_), do: true

  @spec send(pid(), term(), term(), term()) :: :ok
  def send(receiver, destination, apdu, _) do
    Kernel.send(receiver, {:segment_reply, destination, apdu})
    :ok
  end
end
