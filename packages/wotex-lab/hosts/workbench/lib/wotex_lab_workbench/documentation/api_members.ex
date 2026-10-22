defmodule WotexLabWorkbench.Documentation.ApiMembers do
  @moduledoc false

  @groups [
    {"function", "Functions"},
    {"macro", "Macros"},
    {"callback", "Callbacks"},
    {"macrocallback", "Macro callbacks"},
    {"type", "Types"},
    {"opaque", "Opaque types"}
  ]
  @kinds Enum.map(@groups, &elem(&1, 0))
  @max_members 2_048
  @max_member_bytes 262_144
  @max_module_bytes 4_194_304

  @doc false
  @spec project([map()]) :: {:ok, [map()], map()} | {:error, term()}
  def project(collections) do
    initial = {:ok, [], %{included: 0, excluded: 0}}

    result =
      Enum.reduce_while(collections, initial, fn collection, {:ok, acc, totals} ->
        case documents(collection.documents) do
          {:ok, documents, counts} ->
            totals = Map.merge(totals, counts, fn _, a, b -> a + b end)
            {:cont, {:ok, [%{collection | documents: documents} | acc], totals}}

          {:error, _} = error ->
            {:halt, error}
        end
      end)

    case result do
      {:ok, collections, totals} -> {:ok, Enum.reverse(collections), totals}
      error -> error
    end
  end

  @doc false
  @spec index(map()) :: map()
  def index(site) do
    search =
      Enum.map(site.search, fn record ->
        member = site.pages[record.page_id].metadata["api_member"]

        if is_map(member) and is_nil(record.section) do
          %{record | text: record.text <> "\n" <> member["name"]}
        else
          record
        end
      end)

    %{site | search: search}
  end

  defp documents(documents) do
    result =
      Enum.reduce_while(documents, {:ok, [], %{included: 0, excluded: 0}}, fn document,
                                                                              {:ok, acc, totals} ->
        case expand(document) do
          {:ok, expanded, counts} ->
            totals = Map.merge(totals, counts, fn _, a, b -> a + b end)
            {:cont, {:ok, [expanded | acc], totals}}

          {:error, reason} ->
            {:halt, {:error, {:invalid_api_members, document["id"], reason}}}
        end
      end)

    case result do
      {:ok, groups, counts} -> {:ok, Enum.flat_map(Enum.reverse(groups), & &1), counts}
      error -> error
    end
  end

  defp expand(%{"kind" => "module", "meta" => %{"moduledoc" => "hidden", "members" => members}}) do
    with :ok <- validate_members(members),
         do: {:ok, [], %{included: 0, excluded: length(members)}}
  end

  defp expand(%{"kind" => "module", "meta" => %{"members" => members}} = document) do
    with :ok <- validate_members(members),
         {:ok, admitted} <- public_members(members),
         {:ok, pages} <- member_pages(document, admitted) do
      overview = Map.update!(document, "ast", &(&1 ++ member_index(pages)))

      {:ok, [overview | pages],
       %{included: length(pages), excluded: length(members) - length(pages)}}
    end
  end

  defp expand(document), do: {:ok, [document], %{included: 0, excluded: 0}}

  defp validate_members(members) when is_list(members) and length(members) <= @max_members do
    cond do
      not Enum.all?(members, &valid_member?/1) ->
        {:error, :invalid_member}

      Enum.sum(Enum.map(members, &member_bytes/1)) > @max_module_bytes ->
        {:error, :module_too_large}

      true ->
        :ok
    end
  end

  defp validate_members(_), do: {:error, :invalid_member_count}

  defp valid_member?(
         %{
           "kind" => kind,
           "name" => name,
           "arity" => arity,
           "signatures" => signatures,
           "doc" => doc,
           "metadata" => metadata
         } = member
       ) do
    kind in @kinds and is_binary(name) and byte_size(name) in 1..255 and String.valid?(name) and
      is_integer(arity) and arity in 0..255 and valid_signatures?(signatures) and
      is_binary(doc) and String.valid?(doc) and is_map(metadata) and
      Map.get(member, "doc_state", "present") in ["present", "hidden", "none"] and
      member_bytes(member) <= @max_member_bytes
  end

  defp valid_member?(_), do: false

  defp valid_signatures?(signatures) do
    is_list(signatures) and length(signatures) <= 32 and
      Enum.all?(signatures, &(is_binary(&1) and String.valid?(&1)))
  end

  defp member_bytes(member),
    do: byte_size(member["doc"]) + Enum.sum(Enum.map(member["signatures"], &byte_size/1))

  defp public_members(members) do
    admitted =
      Enum.filter(
        members,
        &(Map.get(&1, "doc_state", "present") == "present" and String.trim(&1["doc"]) != "")
      )

    identities = Enum.map(admitted, &{&1["kind"], &1["name"], &1["arity"]})

    if length(identities) == length(Enum.uniq(identities)),
      do:
        {:ok,
         Enum.sort_by(
           admitted,
           &{Enum.find_index(@kinds, fn kind -> kind == &1["kind"] end), &1["name"], &1["arity"]}
         )},
      else: {:error, :duplicate_member}
  end

  defp member_pages(document, members) do
    result =
      Enum.reduce_while(members, {:ok, []}, fn member, {:ok, pages} ->
        case DocShell.Ast.from_markdown(member["doc"]) do
          {:ok, ast} -> {:cont, {:ok, [member_page(document, member, ast) | pages]}}
          {:error, reason} -> {:halt, {:error, {:member_markdown, member["name"], reason}}}
        end
      end)

    case result do
      {:ok, pages} -> {:ok, Enum.reverse(pages)}
      error -> error
    end
  end

  defp member_page(document, member, ast) do
    key =
      member["kind"] <>
        ":" <>
        Base.encode16(member["name"], case: :lower) <> ":" <> Integer.to_string(member["arity"])

    label = member["name"] <> "/" <> Integer.to_string(member["arity"])

    metadata =
      Map.put(document["meta"], "api_member", %{
        "module" => document["document_id"],
        "kind" => member["kind"],
        "name" => member["name"],
        "arity" => member["arity"]
      })
      |> Map.delete("members")

    back = node("p", [node("a", [document["title"]], %{"href" => "doc:" <> document["id"]})])

    signatures =
      Enum.map(
        member["signatures"],
        &node("pre", [node("code", [&1], %{"class" => "language-elixir"})])
      )

    %{
      "id" => document["id"] <> ":" <> key,
      "collection_id" => document["collection_id"],
      "document_id" => document["document_id"] <> ":" <> key,
      "kind" => member["kind"],
      "title" => label,
      "ast" => [back] ++ signatures ++ member_notes(member["metadata"]) ++ ast,
      "meta" => metadata
    }
  end

  defp member_notes(metadata) do
    for {key, label} <- [{"deprecated", "Deprecated"}, {"since", "Since"}],
        value = metadata[key],
        is_binary(value) and value != "",
        do: node("p", [node("strong", [label <> ": "]), value])
  end

  defp member_index(pages) do
    Enum.flat_map(@groups, fn {kind, title} ->
      case Enum.filter(pages, &(&1["kind"] == kind)) do
        [] ->
          []

        members ->
          [
            node("h2", [title]),
            node(
              "ul",
              Enum.map(members, fn page ->
                member = page["meta"]["api_member"]

                node("li", [
                  node(
                    "a",
                    [node("code", [member["name"] <> "/" <> Integer.to_string(member["arity"])])],
                    %{"href" => "doc:" <> page["id"]}
                  )
                ])
              end)
            )
          ]
      end
    end)
  end

  defp node(tag, content, attrs \\ %{}),
    do: %{"tag" => tag, "attrs" => attrs, "content" => content, "meta" => %{}}
end
