defmodule Mix.Tasks.Wotex.Matter.Bridge.Model do
  @shortdoc "Reproduces the pinned Matter bridge model artifacts"
  @moduledoc """
  Reproduces the WMA.09 model in a new disposable workspace.

  Run `mix pkg wotex-matter wotex.matter.bridge.model --sdk /absolute/sdk
  --tools /absolute/tools --workspace /absolute/output` from the repository
  root. Inputs must be explicit absolute directories outside the package.
  The SDK archive and tool packages come from the pinned software-source
  manifest; this task verifies the selected source files and ZAP executable,
  then checks every generated C++ and IDL artifact against its recorded digest.

  Docker runs the generator with networking disabled and both input directories
  mounted read-only. The output directory must not exist. Generation does not
  start a Matter server or qualify a Device Type, commissioning, authorization
  or reporting. Loading the library never invokes this task.
  """

  use Mix.Task

  @impl Mix.Task
  def run(arguments) do
    unless Mix.Project.config()[:app] == :wotex_matter,
      do: Mix.raise("software_fixture_wrong_project")

    runner = Path.expand("test/support/software/bridge_model.exs")
    unless File.regular?(runner), do: Mix.raise("software_fixture_source_required")
    Code.require_file(runner)
    model = Module.safe_concat([Wotex, Matter, SoftwareBridgeModel])
    manifest = Module.safe_concat([Wotex, Matter, SoftwareManifest])

    case arguments do
      ["--sdk", sdk, "--tools", tools, "--workspace", workspace] ->
        root = File.cwd!()
        sdk = manifest.arguments(["--workspace", sdk], root)
        tools = manifest.arguments(["--workspace", tools], root)

        unless File.dir?(sdk) and File.dir?(tools), do: Mix.raise("bridge_model_inputs_required")

        :ok = model.generate!(sdk, tools, workspace)
        Mix.shell().info("Matter bridge model: all seven generated artifact digests match")

      _ ->
        Mix.raise("invalid_bridge_model_arguments")
    end
  end
end
