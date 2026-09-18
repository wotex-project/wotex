%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/", "config/", "bin/", "mix_tasks/", "mix.exs"]},
      strict: true,
      checks: %{extra: [{Credo.Check.Readability.MaxLineLength, [max_length: 100]}]}
    }
  ]
}
