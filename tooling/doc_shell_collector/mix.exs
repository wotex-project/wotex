defmodule Wotex.DocShellCollector.MixProject do
  use Mix.Project

  def project do
    [
      app: :wotex_doc_shell_collector,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [
        {:doc_shell, "== 0.4.0", runtime: false}
      ]
    ]
  end

  def application, do: [extra_applications: []]
end
