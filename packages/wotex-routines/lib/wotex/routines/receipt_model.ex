defmodule Wotex.Routines.ReceiptModel do
  @moduledoc false

  @phases ~w(proposed reserved handed completed refused failed unknown cancelled)

  @doc false
  @spec bytes(boolean()) :: String.t()
  def bytes(value) do
    rules = [
      {"manual-first", "fresh, 0, 0, false, none, false", "proposed, 1, 0, false, none, false"},
      {"held", "proposed, 1, 0, false, none, false", "reserved, 1, 1, false, none, false"},
      {"refused", "proposed, 1, 0, false, none, false", "refused, 1, 0, false, none, true"},
      {"handoff", "reserved, 1, 1, false, none, false", "handed, 1, 1, true, none, false"},
      {"ack", "handed, 1, 1, true, none, false", "handed, 1, 1, true, ack, false"},
      {"ack-repeat", "handed, 1, 1, true, ack, false", "handed, 1, 1, true, ack, false"},
      {"match", "handed, 1, 1, true, none, false", "completed, 1, 1, true, match, true"},
      {"match-after-ack", "handed, 1, 1, true, ack, false", "completed, 1, 1, true, match, true"},
      {"failed", "handed, 1, 1, true, none, false", "failed, 1, 1, true, none, true"},
      {"unknown", "handed, 1, 1, true, none, false", "unknown, 1, 1, true, none, true"},
      {"cancel-proposed", "proposed, 1, 0, false, none, false",
       "cancelled, 1, 0, false, none, true"},
      {"cancel-reserved", "reserved, 1, 1, false, none, false",
       "cancelled, 1, 1, false, none, true"},
      {"cancel-handed", "handed, 1, 1, true, none, false", "unknown, 1, 1, true, none, true"},
      {"cancel-acked", "handed, 1, 1, true, ack, false", "unknown, 1, 1, true, ack, true"}
    ]

    manual = Enum.map(@phases, &identity("manual-" <> &1, &1))
    repeats = Enum.map(~w(reserved handed), &identity("held-repeat-" <> &1, &1))
    handoff = identity("handoff-repeat", "handed")

    stopped =
      Enum.map(~w(completed refused failed unknown cancelled), &identity("cancel-" <> &1, &1))

    literal = if value, do: "true", else: "false"

    """
    mod ROUTINE-RECEIPT-PREFIX is
      protecting NAT .
      protecting BOOL .
      sorts Phase Evidence State .
      ops fresh proposed reserved handed completed refused failed unknown cancelled : -> Phase [ctor] .
      ops none ack match : -> Evidence [ctor] .
      op state : Phase Nat Nat Bool Evidence Bool -> State [ctor] .
      op requested : -> Bool .
      eq requested = #{literal} .
    #{Enum.map_join(rules ++ manual ++ repeats ++ [handoff] ++ stopped, "\n", &rule/1)}
    endm
    """
  end

  defp identity(label, phase) do
    state = phase <> ", N:Nat, S:Nat, H:Bool, E:Evidence, Z:Bool"
    {label, state, state}
  end

  defp rule({label, left, right}), do: "  rl [#{label}] : state(#{left}) => state(#{right}) ."
end
