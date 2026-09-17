# Deterministic public-export and typespec snapshot for explicit compatibility
# review. Runs through Mix after compilation:
# `mix run --no-start bin/generate_api_surface.exs --check|--write`.

defmodule Wotex.Lab.Check.ApiSurface do
  @moduledoc false

  @ignored [__info__: 1, module_info: 0, module_info: 1]

  def run(args) do
    root = Path.expand("..", __DIR__)
    output = Path.join(root, "priv/provenance/wotex-lab-api.json")
    bytes = JSON.encode!(surface()) <> "\n"

    case args do
      ["--check"] ->
        File.read(output) == {:ok, bytes} || abort("public API snapshot is stale; run with --write")

        IO.puts(
          "public API: exported functions, behaviours, structs and typespecs match the review"
        )

      ["--write"] ->
        File.write!(output, bytes)
        IO.puts("public API: wrote #{output}")

      _other ->
        abort("usage: mix run --no-start bin/generate_api_surface.exs --check|--write")
    end
  end

  defp surface do
    modules =
      case :application.get_key(:wotex_lab, :modules) do
        {:ok, modules} -> modules
        :undefined -> abort("wotex_lab application metadata is unavailable")
      end

    %{
      "schema_version" => "1.0.0",
      "package" => "wotex_lab",
      "version" => to_string(Application.spec(:wotex_lab, :vsn)),
      "compatibility_status" => "pre-1.0-review-baseline",
      "modules" =>
        modules |> Enum.reject(&support_module?/1) |> Enum.sort() |> Enum.map(&module_surface/1)
    }
  end

  # Test support is compiled into the application under MIX_ENV=test and is not
  # part of the reviewed public API.
  defp support_module?(module),
    do: String.starts_with?(Atom.to_string(module), "Elixir.Wotex.Lab.Test.")

  defp module_surface(module) do
    Code.ensure_loaded!(module)

    functions =
      module.module_info(:exports)
      |> Enum.reject(&(&1 in @ignored))
      |> Enum.sort()
      |> Enum.map(fn {name, arity} -> %{"name" => Atom.to_string(name), "arity" => arity} end)

    %{
      "module" => Atom.to_string(module),
      "behaviours" => behaviours(module),
      "struct_keys" => struct_keys(module),
      "functions" => functions,
      "specs" => specs(module)
    }
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.sort()
  end

  defp struct_keys(module) do
    if function_exported?(module, :__struct__, 0) do
      module.__struct__()
      |> Map.keys()
      |> Enum.reject(&(&1 == :__struct__))
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()
    else
      []
    end
  end

  defp specs(module) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} ->
        specs
        |> Enum.flat_map(fn {{name, arity}, clauses} ->
          Enum.map(clauses, fn clause ->
            quoted = Code.Typespec.spec_to_quoted(name, clause)

            %{
              "name" => Atom.to_string(name),
              "arity" => arity,
              "contract" => Macro.to_string(quoted)
            }
          end)
        end)
        |> Enum.sort_by(&{&1["name"], &1["arity"], &1["contract"]})

      :error ->
        []
    end
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.ApiSurface.run(System.argv())
