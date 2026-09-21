# Deterministic public-export and typespec snapshot for explicit compatibility
# review. Runs through Mix after compilation:
# `mix run --no-start bin/generate_api_surface.exs --check|--write`.

defmodule Wotex.Lab.Check.ApiSurface do
  @moduledoc false

  @ignored [__info__: 1, module_info: 0, module_info: 1]

  @spec run([String.t()]) :: :ok
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

      _ ->
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
      "schema_version" => "2.0.0",
      "package" => "wotex_lab",
      "version" => to_string(Application.spec(:wotex_lab, :vsn)),
      "compatibility_status" => "pre-1.0-review-baseline",
      "modules" =>
        modules
        |> Enum.reject(&support_module?/1)
        |> Enum.sort()
        |> Enum.map(&module_surface/1)
    }
  end

  # Test support is compiled into the application under MIX_ENV=test and is not
  # part of the reviewed public API.
  defp support_module?(module),
    do: String.starts_with?(Atom.to_string(module), "Elixir.Wotex.Lab.Test.")

  defp module_surface(module) do
    Code.ensure_loaded!(module)
    documentation = documentation(module)

    functions =
      module.module_info(:exports)
      |> Enum.reject(&(&1 in @ignored))
      |> Enum.sort()
      |> Enum.map(&function_surface(&1, documentation.functions))

    %{
      "module" => Atom.to_string(module),
      "behaviours" => behaviours(module),
      "struct_keys" => struct_keys(module),
      "documentation" => documentation.module,
      "functions" => functions,
      "specs" => specs(module)
    }
  end

  defp documentation(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, module_doc, _, entries} ->
        %{
          module: documentation_value(module_doc),
          functions:
            entries
            |> Enum.flat_map(&documentation_entry/1)
            |> Map.new()
        }

      {:error, reason} ->
        abort("documentation metadata is unavailable for #{inspect(module)}: #{inspect(reason)}")
    end
  end

  defp documentation_entry({{kind, name, arity}, _, signatures, doc, metadata})
       when kind in [:function, :macro] do
    {export_name, export_arity} =
      if kind == :macro, do: {"MACRO-#{name}", arity + 1}, else: {Atom.to_string(name), arity}

    value =
      documentation_value(doc)
      |> Map.put("signatures", signatures)
      |> put_defaults(metadata)

    [{{export_name, export_arity}, value}]
  end

  defp documentation_entry(_), do: []

  defp documentation_value(%{"en" => text}) when is_binary(text) and text != "" do
    %{"status" => "documented", "sha256" => digest(text)}
  end

  defp documentation_value(:hidden), do: %{"status" => "hidden"}
  defp documentation_value(:none), do: %{"status" => "missing"}

  defp documentation_value(other),
    do: abort("unsupported documentation metadata: #{inspect(other)}")

  defp function_surface({name, arity}, documentation) do
    name = Atom.to_string(name)

    %{"name" => name, "arity" => arity}
    |> Map.put("documentation", Map.get(documentation, {name, arity}, %{"status" => "missing"}))
  end

  defp put_defaults(value, metadata) do
    case Map.get(metadata, :defaults) do
      count when is_integer(count) and count > 0 -> Map.put(value, "defaults", count)
      _ -> value
    end
  end

  defp digest(bytes),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

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
