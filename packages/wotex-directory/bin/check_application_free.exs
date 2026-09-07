# Verifies that the library defines no application callback.
#
#     mix run --no-start bin/check_application_free.exs

unless Application.spec(:wotex_directory, :mod) in [nil, [], :undefined], do: System.halt(1)
