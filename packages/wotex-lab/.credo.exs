# Strict checks come from the repository's root `.credo.exs`. Lab also lints
# its bin/ verification commands and mix.exs; the stdout report of a bin/
# command is its interface, so IO.puts is allowed there.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "bin/", "mix.exs"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: %{extra: [{Credo.Check.Refactor.IoPuts, [files: %{excluded: ["bin/"]}]}]}
    }
  ]
}
