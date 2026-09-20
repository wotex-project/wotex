import Config

project = Mix.Project.config()
app = project |> Keyword.fetch!(:app) |> Atom.to_string()
repository_path = System.fetch_env!("WOTEX_DOC_SHELL_REPOSITORY_PATH")
source_root = System.fetch_env!("WOTEX_DOC_SHELL_SOURCE_ROOT")
public_dir = System.fetch_env!("WOTEX_DOC_SHELL_PUBLIC_DIR")

guide_bases =
  "WOTEX_DOC_SHELL_GUIDE_BASES"
  |> System.fetch_env!()
  |> JSON.decode!()

config :doc_shell,
  title: Keyword.get(project, :name, app),
  api_version: Keyword.fetch!(project, :version),
  public_dir: public_dir,
  private_dir: System.fetch_env!("WOTEX_DOC_SHELL_PRIVATE_DIR"),
  guide_bases: guide_bases,
  livebook_base: source_root,
  changelog_source: false,
  search_members: true,
  collection: [
    id: app,
    title: Keyword.get(project, :name, app),
    version: Keyword.fetch!(project, :version),
    revision: System.fetch_env!("WOTEX_DOC_SHELL_REVISION"),
    tree_digest: System.fetch_env!("WOTEX_DOC_SHELL_TREE_DIGEST"),
    artifact_dir: public_dir,
    source_url:
      System.fetch_env!("WOTEX_DOC_SHELL_REPOSITORY_URL") <>
        "/tree/" <> System.fetch_env!("WOTEX_DOC_SHELL_REVISION"),
    edit_base_url:
      System.fetch_env!("WOTEX_DOC_SHELL_REPOSITORY_URL") <>
        "/edit/" <> System.fetch_env!("WOTEX_DOC_SHELL_EDIT_BRANCH"),
    package: app,
    license: System.fetch_env!("WOTEX_DOC_SHELL_LICENSE"),
    source_root: source_root,
    status: "stable"
  ]
