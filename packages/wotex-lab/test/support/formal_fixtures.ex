defmodule Wotex.Lab.Test.FormalFixtures do
  @moduledoc false

  # Verbatim Maude 3.5.1 replies captured from priv/models/thermal-control-v1.maude
  # so the parsers and the replay are exercised without the executable.

  @spec safe_no_solution() :: String.t()
  def safe_no_solution do
    """
    search [1] in SAFE-THERMAL : init =>* room(B, on, on, E, D:Decision, A, G, N) .

    No solution.
    states: 253  rewrites: 1785 in 0ms cpu (0ms real) (4811320 rewrites/second)
    """
  end

  @spec bounded_no_solution() :: String.t()
  def bounded_no_solution do
    """
    search [1, 2] in SAFE-THERMAL : init =>* room(B, on, on, E, D:Decision, A, G, N) .

    No solution.
    states: 9  rewrites: 31 in 0ms cpu (0ms real) (~ rewrites/second)
    """
  end

  @spec broken_energy_solution() :: String.t()
  def broken_energy_solution do
    """
    search [1, 100] in BROKEN-ENERGY : init =>* room(B, on, C, over, D:Decision, A, G, N) .

    Solution 1 (state 5)
    states: 6  rewrites: 15 in 0ms cpu (0ms real) (~ rewrites/second)
    B --> cold
    C --> off
    D:Decision --> dispatched(heat, 0)
    A --> 0
    G --> 1
    N --> 1
    """
  end

  @spec broken_energy_path() :: String.t()
  def broken_energy_path do
    """
    state 0, Room: room(comfort, off, off, within, noDecision, 0, 0, 0)
    ===[ rl [coolDown] : room(comfort, H, C, E, noDecision, A, G, N) => room(cold, H, C, E, noDecision, A, G, N) . ]===>
    state 1, Room: room(cold, off, off, within, noDecision, 0, 0, 0)
    ===[ crl [proposeHeat] : room(cold, H, C, within, noDecision, A, G, N) => room(cold, H, C, within, granted(heat, A), A, G + 1, N) if G < maxGrants = true . ]===>
    state 2, Room: room(cold, off, off, within, granted(heat, 0), 0, 1, 0)
    ===[ rl [energyOver] : room(B, H, C, within, granted(X, T), A, G, N) => room(B, off, C, over, granted(X, T), A, G, N) . ]===>
    state 3, Room: room(cold, off, off, over, granted(heat, 0), 0, 1, 0)
    ===[ crl [dispatchHeat] : room(B, H, C, E, granted(heat, T), A, G, N) => room(B, on, off, E, dispatched(heat, A), 0, G, N + 1) if A < maxAge = true . ]===>
    state 5, Room: room(cold, on, off, over, dispatched(heat, 0), 0, 1, 1)
    """
  end

  # A path of the safe model to a good state: cold, heater on after one grant.
  @spec safe_heating_path() :: String.t()
  def safe_heating_path do
    """
    state 0, Room: room(comfort, off, off, within, noDecision, 0, 0, 0)
    ===[ rl [coolDown] : room(comfort, H, C, E, noDecision, A, G, N) => room(cold, H, C, E, noDecision, A, G, N) . ]===>
    state 1, Room: room(cold, off, off, within, noDecision, 0, 0, 0)
    ===[ crl [tick] : room(B, H, C, E, noDecision, A, G, N) => room(B, H, C, E, noDecision, A + 1, G, N) if A < maxAge = true . ]===>
    state 2, Room: room(cold, off, off, within, noDecision, 1, 0, 0)
    ===[ crl [proposeHeat] : room(cold, H, C, within, noDecision, A, G, N) => room(cold, H, C, within, granted(heat, A), A, G + 1, N) if G < maxGrants = true . ]===>
    state 3, Room: room(cold, off, off, within, granted(heat, 1), 1, 1, 0)
    ===[ crl [age] : room(B, H, C, E, granted(X, T), A, G, N) => room(B, H, C, E, granted(X, T), A + 1, G, N) if A < maxAge = true . ]===>
    state 4, Room: room(cold, off, off, within, granted(heat, 1), 2, 1, 0)
    ===[ crl [dispatchHeat] : room(B, H, C, within, granted(heat, T), A, G, N) => room(B, on, off, within, dispatched(heat, A), 0, G, N + 1) if A < maxAge = true . ]===>
    state 5, Room: room(cold, on, off, within, dispatched(heat, 2), 0, 1, 1)
    ===[ rl [complete] : room(B, H, C, E, dispatched(X, T), A, G, N) => room(B, H, C, E, noDecision, A, G, N) . ]===>
    state 6, Room: room(cold, on, off, within, noDecision, 0, 1, 1)
    """
  end

  # A duplicate delivery in the broken model creates a second effect.
  @spec broken_duplicate_path() :: String.t()
  def broken_duplicate_path do
    """
    state 0, Room: room(comfort, off, off, within, noDecision, 0, 0, 0)
    ===[ rl [heatUp] : room(comfort, H, C, E, noDecision, A, G, N) => room(hot, H, C, E, noDecision, A, G, N) . ]===>
    state 1, Room: room(hot, off, off, within, noDecision, 0, 0, 0)
    ===[ crl [proposeCool] : room(hot, H, C, E, noDecision, A, G, N) => room(hot, H, C, E, granted(cool, A), A, G + 1, N) if G < maxGrants = true . ]===>
    state 2, Room: room(hot, off, off, within, granted(cool, 0), 0, 1, 0)
    ===[ crl [dispatchCool] : room(B, H, C, E, granted(cool, T), A, G, N) => room(B, off, on, E, dispatched(cool, A), 0, G, N + 1) if A < maxAge = true . ]===>
    state 3, Room: room(hot, off, on, within, dispatched(cool, 0), 0, 1, 1)
    ===[ rl [redeliver] : room(B, H, C, E, dispatched(X, T), A, G, N) => room(B, H, C, E, dispatched(X, T), A, G, N + 1) . ]===>
    state 4, Room: room(hot, off, on, within, dispatched(cool, 0), 0, 1, 2)
    """
  end

  @spec warning() :: String.t()
  def warning, do: "Warning: \"probe.maude\", line 7: no module NO-SUCH-MODULE.\n"
end
