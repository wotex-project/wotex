%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "storybook/", "test/", "config/", "tools/", "mix.exs"]},
      strict: true,
      checks: %{extra: [{Credo.Check.Readability.MaxLineLength, [max_length: 100]}]}
    }
  ]
}
