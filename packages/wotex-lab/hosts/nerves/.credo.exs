# Strict checks come from the Lab configuration two directories up; this file
# only adds the host's config/ directory to the linted sources.
%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/", "config/", "mix.exs"]},
      strict: true
    }
  ]
}
