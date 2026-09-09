%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/", "mix.exs"]},
      strict: true,
      checks: %{
        enabled: [{Credo.Check.Consistency.UnusedVariableNames, [force: :anonymous]}],
        extra: [{Credo.Check.Readability.MaxLineLength, [max_length: 100]}]
      }
    }
  ]
}
