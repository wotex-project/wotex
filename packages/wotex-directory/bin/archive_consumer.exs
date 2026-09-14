# Runs only inside the generated archive consumer, never the source checkout.

unless File.dir?("packages/wotex_directory") and File.dir?("packages/wotex"),
  do: raise("archive consumer packages are missing")

unless System.get_env("WOTEX_PATH_DEPS") == nil, do: raise("path development mode is forbidden")

Mix.Task.run("deps.compile")

for dependency <- Mix.Dep.cached() do
  unless String.starts_with?(Path.expand(dependency.opts[:dest]), File.cwd!() <> "/"),
    do: raise("dependency source is outside the archive consumer")
end

# Mix deliberately disables warnings-as-errors during dependency compilation.
# Recompile each owned archive in its dependency context with the flag enabled.
for dependency <- Mix.Dep.cached(), dependency.app in [:wotex, :wotex_directory] do
  Mix.Dep.in_dependency(dependency, fn _ ->
    Mix.Task.reenable("compile")
    Mix.Task.reenable("compile.all")
    Mix.Task.reenable("compile.elixir")
    Mix.Task.run("compile", ["--force", "--warnings-as-errors", "--no-deps-check"])
  end)
end

Mix.Task.reenable("compile")
Mix.Task.run("compile", ["--warnings-as-errors"])

started = Application.started_applications()
build = Path.expand("_build/prod/lib") <> "/"

for app <- [:wotex, :wotex_directory] do
  unless Application.load(app) in [:ok, {:error, {:already_loaded, app}}],
    do: raise("could not load archived application metadata")

  unless Application.spec(app, :mod) in [nil, [], :undefined],
    do: raise("archived library defines an application callback")

  unless Enum.all?(Application.spec(app, :modules), fn module ->
           {:module, ^module} = Code.ensure_loaded(module)
           module |> :code.which() |> List.to_string() |> String.starts_with?(build)
         end),
         do: raise("library module loaded outside the isolated archive build")

  if Enum.any?(started, fn {name, _, _} -> name == app end),
    do: raise("archived library was implicitly started")
end

unless Application.started_applications() == started,
  do: raise("loading archive modules started an application")

IO.puts("archive modules loaded only from the isolated build; no library application startup")
ExUnit.start(autorun: false)
Code.require_file("archive_consumer_test.exs")
result = ExUnit.run()
unless result.failures == 0, do: raise("archive consumer contract failures")
