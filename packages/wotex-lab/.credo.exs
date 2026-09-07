%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/", "mix.exs"]},
      strict: true,
      checks: %{extra: [{Credo.Check.Readability.MaxLineLength, [max_length: 100]}]}
    }
  ]
}
