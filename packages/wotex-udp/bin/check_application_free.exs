unless Application.spec(:wotex_udp, :mod) in [nil, [], :undefined] do
  IO.puts(:stderr, "wotex_udp must not start an application callback")
  System.halt(1)
end
