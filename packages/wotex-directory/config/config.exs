import Config

if config_env() == :dev do
  config :git_ops,
    mix_project: Mix.Project.get!(),
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/wotex-project/wotex-directory",
    version_tag_prefix: "v",
    manage_mix_version?: true,
    manage_readme_version: false,
    github_handle_lookup?: false,
    types: [
      chore: [hidden?: true],
      test: [hidden?: true],
      ci: [hidden?: true],
      build: [hidden?: true],
      style: [hidden?: true]
    ]
end
