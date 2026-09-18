defmodule Wotex.Workspace.ModuleSpans do
  @moduledoc """
  The line spans of the modules defined in an Elixir source file, and the
  innermost module enclosing a line.

  `defmodule` and `defprotocol` blocks are recognised, including nested
  ones (`defmodule Inner` inside `Outer` is `Outer.Inner`) and
  `__MODULE__.Inner` names. The analysis is syntactic: a module that a macro
  generates has no span of its own, and a module with a computed name (for
  example `unquote(name)`) is attributed to the enclosing module. A literally
  named `defmodule` inside a `quote` is nested like any other.
  """

  @type span :: %{module: String.t(), first: pos_integer(), last: pos_integer()}

  @doc "The module spans of `source`, outermost first."
  @spec spans(String.t(), Path.t()) :: {:ok, [span()]} | {:error, String.t()}
  def spans(source, file \\ "nofile") do
    case Code.string_to_quoted(source,
           file: file,
           columns: false,
           token_metadata: true,
           emit_warnings: false
         ) do
      {:ok, ast} ->
        {:ok, Enum.reverse(collect(ast, nil, []))}

      {:error, {meta, message, token}} ->
        {:error,
         "#{file}:#{Keyword.get(List.wrap(meta), :line, 0)}: cannot be parsed: " <>
           format_error(message, token)}
    end
  end

  @doc """
  The innermost module of `source` whose span contains `line`, or `nil`
  when the line is outside every module.
  """
  @spec enclosing(String.t(), pos_integer(), Path.t()) ::
          {:ok, String.t() | nil} | {:error, String.t()}
  def enclosing(source, line, file \\ "nofile") do
    with {:ok, spans} <- spans(source, file) do
      innermost =
        spans
        |> Enum.filter(&(&1.first <= line and line <= &1.last))
        |> Enum.max_by(&{&1.first, -&1.last}, fn -> nil end)

      {:ok, innermost && innermost.module}
    end
  end

  defp collect({kind, meta, [name, [{:do, body} | _rest]]}, parent, acc)
       when kind in [:defmodule, :defprotocol] do
    case module_name(name, parent) do
      nil ->
        collect(body, parent, acc)

      module ->
        first = Keyword.get(meta, :line, 1)
        last = end_line(meta, body, first)
        collect(body, module, [%{module: module, first: first, last: last} | acc])
    end
  end

  defp collect({form, _meta, args}, parent, acc) when is_list(args) do
    collect(args, parent, collect(form, parent, acc))
  end

  defp collect({left, right}, parent, acc), do: collect(right, parent, collect(left, parent, acc))

  defp collect(list, parent, acc) when is_list(list),
    do: Enum.reduce(list, acc, &collect(&1, parent, &2))

  defp collect(_other, _parent, acc), do: acc

  defp module_name({:__aliases__, _meta, [{:__MODULE__, _, _} | rest]}, parent)
       when is_binary(parent) do
    if Enum.all?(rest, &is_atom/1), do: join([parent | rest]), else: nil
  end

  defp module_name({:__aliases__, _meta, parts}, parent) do
    if Enum.all?(parts, &is_atom/1) do
      name = join(parts)

      cond do
        String.starts_with?(name, "Elixir.") -> String.replace_prefix(name, "Elixir.", "")
        parent -> parent <> "." <> name
        true -> name
      end
    end
  end

  defp module_name(atom, _parent) when is_atom(atom) and atom not in [nil, true, false],
    do: String.replace_prefix(Atom.to_string(atom), "Elixir.", "")

  defp module_name(_other, _parent), do: nil

  defp join(parts), do: Enum.map_join(parts, ".", &to_string/1)

  # `do ... end` blocks carry their closing line; the keyword form
  # (`defmodule A, do: ...`) ends at the last line of its body.
  defp end_line(meta, body, first) do
    case get_in(meta, [:end, :line]) do
      line when is_integer(line) -> line
      nil -> max_line(body, first)
    end
  end

  defp max_line(ast, floor) do
    {_ast, max} =
      Macro.prewalk(ast, floor, fn
        {_form, meta, _args} = node, max when is_list(meta) ->
          {node, max(max, Keyword.get(meta, :line, max))}

        node, max ->
          {node, max}
      end)

    max
  end

  defp format_error({prefix, suffix}, token), do: "#{prefix}#{token}#{suffix}"
  defp format_error(message, token), do: "#{message}#{token}"
end
