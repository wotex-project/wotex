%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/", "config/", "mix.exs"]},
      strict: true,
      checks: %{extra: [{Credo.Check.Readability.MaxLineLength, [max_length: 100]}]}
    }
  ]
}
