defmodule Wotex.Profiles.Reader do
  @moduledoc false

  alias Wotex.Profiles.{Error, Grammar, Numeric, Schema, Unit}

  @scalars ~w(null boolean text bytes sint uint decimal)
  @fingerprint ~w(boolean text sint uint)
  @operations Map.new(Wotex.Runtime.operations(), fn operation ->
                {Atom.to_string(operation), Wotex.Runtime.interaction_type(operation)}
              end)

  @doc false
  @spec new(:profile | :definition, term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def new(kind, input, limits) do
    with {:ok, data} <- unwrap(kind, input),
         {:ok, data, limits} <- Grammar.admit(data, limits),
         :ok <- validate(kind, data, limits),
         {:ok, identity} <- Grammar.identity(prefix(kind), data, limits) do
      {:ok, %{data: data, raw_sha256: nil, semantic_sha256: identity}}
    end
  end

  defp unwrap(
         kind,
         %{__struct__: module, data: data, raw_sha256: raw, semantic_sha256: digest} = value
       )
       when map_size(value) == 4 do
    expected = if kind == :profile, do: Wotex.Profiles.Profile, else: Wotex.Profiles.Definition

    with true <- module == expected, :ok <- Grammar.digest(digest, ""), :ok <- raw_identity(raw) do
      {:ok, data}
    else
      _ -> Error.refusal(:invalid_input)
    end
  end

  defp unwrap(_, data) when is_map(data) and not is_struct(data), do: {:ok, data}
  defp unwrap(_, _), do: Error.refusal(:invalid_input)
  defp raw_identity(nil), do: :ok
  defp raw_identity(digest), do: Grammar.digest(digest, "")

  defp prefix(:profile), do: "wotex.profile.semantic@1"
  defp prefix(:definition), do: "wotex.definition.semantic@1"

  defp common(data, required, format, limits) do
    with :ok <- Grammar.fields(data, required, "", ["annotations"]),
         true <- data["format"] == format,
         :ok <- Grammar.id(data["id"], "/id"),
         :ok <- Grammar.version(data["version"], "/version"),
         :ok <- Grammar.references(data["requires"], limits, "/requires") do
      Grammar.optional_annotations(data)
    else
      false -> Error.refusal(:unsupported_format, "/format")
      error -> error
    end
  end

  defp validate(:definition, data, limits) do
    with :ok <-
           common(
             data,
             ~w(format id version value_schema unit behaviour requires),
             "wotex.semantic@1",
             limits
           ),
         :ok <- Schema.check(data["value_schema"], limits, "/value_schema"),
         :ok <- unit(data["unit"], limits) do
      behaviour(data["behaviour"])
    end
  end

  defp validate(:profile, data, limits) do
    with :ok <-
           common(
             data,
             ~w(format id version binding fingerprint channels requires),
             "wotex.profile@1",
             limits
           ),
         :ok <- Grammar.reference(data["binding"], "/binding"),
         :ok <- fingerprint(data["fingerprint"]) do
      channels(data["channels"], limits)
    end
  end

  defp unit(nil, _), do: :ok

  defp unit(value, limits) do
    case Unit.new(value, limits) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp behaviour(nil), do: :ok
  defp behaviour(value), do: Grammar.reference(value, "/behaviour")

  defp fingerprint(values) when is_list(values) and length(values) in 1..32 do
    Grammar.each(Enum.with_index(values), fn {value, index} ->
      path = "/fingerprint/" <> Integer.to_string(index)

      with :ok <- Grammar.fields(value, ~w(field operator values), path),
           :ok <- Grammar.key(value["field"], path <> "/field"),
           true <- value["operator"] in ~w(eq one_of),
           :ok <- Grammar.unique_scalars(value["values"], 32, @fingerprint, path <> "/values"),
           true <- length(value["values"]) >= 1,
           true <- value["operator"] != "eq" or length(value["values"]) == 1 do
        :ok
      else
        false -> Error.refusal(:invalid_input, path)
        error -> error
      end
    end)
  end

  defp fingerprint(_), do: Error.refusal(:invalid_input, "/fingerprint")

  defp channels(values, limits) when is_list(values) do
    with true <- length(values) in 1..limits.data["max_channels"],
         :ok <-
           Grammar.each(Enum.with_index(values), fn {value, index} ->
             channel(value, limits, "/channels/" <> Integer.to_string(index))
           end) do
      Grammar.sorted_unique(values, & &1["id"], "/channels")
    else
      false -> Error.refusal(:input_limit, "/channels")
      error -> error
    end
  end

  defp channels(_, _), do: Error.refusal(:invalid_input, "/channels")

  defp channel(data, limits, path) do
    with :ok <-
           Grammar.fields(
             data,
             ~w(id affordance semantic operations selector conversion invalid_values required),
             path
           ),
         :ok <- Grammar.key(data["id"], path <> "/id"),
         :ok <- affordance(data["affordance"], path <> "/affordance"),
         :ok <- operations(data["operations"], data["affordance"]["kind"], path <> "/operations"),
         :ok <- Grammar.reference(data["semantic"], path <> "/semantic"),
         true <- is_map(data["selector"]) and not is_struct(data["selector"]),
         true <- is_boolean(data["required"]),
         :ok <-
           Grammar.unique_scalars(data["invalid_values"], 32, @scalars, path <> "/invalid_values") do
      conversion(data["conversion"], limits, path <> "/conversion")
    else
      false -> Error.refusal(:invalid_input, path)
      error -> error
    end
  end

  defp affordance(data, path) do
    with :ok <- Grammar.fields(data, ~w(kind name), path),
         true <- data["kind"] in ~w(property action event) do
      Grammar.text(data["name"], 128, path <> "/name")
    else
      false -> Error.refusal(:invalid_input, path)
      error -> error
    end
  end

  defp operations(values, kind, path) when is_list(values) and values != [] do
    if values == Enum.sort(Enum.uniq(values)) and
         Enum.all?(values, fn value ->
           case @operations[value] do
             nil -> false
             type -> Atom.to_string(type) == kind
           end
         end), do: :ok, else: Error.refusal(:invalid_input, path)
  end

  defp operations(_, _, path), do: Error.refusal(:invalid_input, path)

  defp conversion(nil, _, _), do: :ok

  defp conversion(%{"kind" => "affine"} = data, _, path) do
    with :ok <- Grammar.fields(data, ~w(kind scale_n scale_d offset_n offset_d), path),
         :ok <- Numeric.rational(data, "scale_n", "scale_d", true, path) do
      Numeric.rational(data, "offset_n", "offset_d", false, path)
    end
  end

  defp conversion(%{"kind" => "table"} = data, _, path) do
    with :ok <- Grammar.fields(data, ~w(kind entries), path),
         true <- is_list(data["entries"]) and length(data["entries"]) in 1..256,
         :ok <-
           Grammar.each(data["entries"], fn entry ->
             with :ok <- Grammar.fields(entry, ~w(source target), path <> "/entries"),
                  :ok <- Grammar.scalar(entry["source"], @scalars, path <> "/entries/source") do
               Grammar.scalar(entry["target"], @scalars, path <> "/entries/target")
             end
           end) do
      Grammar.sorted_unique(
        data["entries"],
        fn entry ->
          {:ok, bytes} = Wotex.Runtime.Codec.Value.encode(entry["source"])
          bytes
        end,
        path <> "/entries"
      )
    else
      false -> Error.refusal(:input_limit, path)
      error -> error
    end
  end

  defp conversion(_, _, path), do: Error.refusal(:unsupported_semantics, path)
end
