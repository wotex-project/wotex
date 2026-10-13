import Config

if config_env() == :docs and System.get_env("WOTEX_DOC_SHELL_BUILD") == "1" do
  import_config "../../../tooling/doc_shell/package.exs"
end
