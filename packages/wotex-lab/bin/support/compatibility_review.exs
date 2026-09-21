defmodule Wotex.Lab.Check.CompatibilityReview do
  @moduledoc false

  @schema "wotex-lab-compatibility-review/v1"
  @api_schema "2.0.0"
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @documentation_statuses ~w(documented hidden missing)

  @gates [
    %{
      "id" => "foundation_green",
      "state" => "source_implemented",
      "command" => "mix check.fast --package wotex-lab"
    },
    %{
      "id" => "package_contents_green",
      "state" => "source_implemented",
      "command" => "mix pkg wotex-lab run --no-start bin/check_package.exs"
    },
    %{
      "id" => "archive_consumer_green",
      "state" => "source_implemented",
      "command" =>
        "WOTEX_PATH_DEPS=1 mix pkg wotex-lab run --no-start bin/check_archive_consumer.exs"
    },
    %{
      "id" => "workbench_archive_green",
      "state" => "source_implemented",
      "command" =>
        "WOTEX_PATH_DEPS=1 mix pkg wotex-lab run --no-start bin/check_workbench_archive.exs"
    },
    %{
      "id" => "reference_consumer_green",
      "state" => "source_implemented",
      "command" =>
        "WOTEX_PATH_DEPS=1 mix pkg wotex-lab run --no-start bin/check_reference_consumer.exs"
    },
    %{
      "id" => "documentation_distribution_green",
      "state" => "source_implemented",
      "command" => "mix wotex_lab.docs.build --profile release"
    },
    %{
      "id" => "distribution_green",
      "state" => "qualification_required",
      "command" => nil
    },
    %{
      "id" => "public_release_candidate",
      "state" => "maintainer_decision_required",
      "command" => nil
    },
    %{
      "id" => "stable_api_candidate",
      "state" => "maintainer_decision_required",
      "command" => nil
    }
  ]

  @decisions [
    %{
      "id" => "publication",
      "state" => "maintainer_decision_required",
      "reason" => "Publishing packages, images, firmware or sites is not a repository tool action."
    },
    %{
      "id" => "release_candidate",
      "state" => "maintainer_decision_required",
      "reason" =>
        "A release decision requires the selected qualification cohort and security review."
    },
    %{
      "id" => "stable_api",
      "state" => "maintainer_decision_required",
      "reason" => "The pre-1.0 baseline is review input and cannot grant API stability."
    }
  ]

  @spec build(map(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def build(api, api_digest, lanes) do
    with :ok <- validate_api(api),
         true <- digest?(api_digest),
         {:ok, toolchains} <- toolchains(lanes) do
      {:ok,
       %{
         "schema_version" => @schema,
         "package" => api["package"],
         "version" => api["version"],
         "review_status" => "pre-1.0-readiness-inputs",
         "api_baseline" => baseline(api, api_digest),
         "toolchains" => toolchains,
         "gates" => @gates,
         "decisions" => @decisions
       }}
    else
      false -> {:error, :invalid_compatibility_review_input}
      {:error, _} = error -> error
    end
  end

  @spec validate(term()) :: :ok | {:error, term()}
  def validate(
        %{
          "schema_version" => @schema,
          "package" => package,
          "version" => version,
          "review_status" => "pre-1.0-readiness-inputs",
          "api_baseline" => baseline,
          "toolchains" => toolchains,
          "gates" => gates,
          "decisions" => decisions
        } = review
      ) do
    with true <- map_size(review) == 8,
         true <- package == "wotex_lab",
         true <- version?(version),
         :ok <- validate_baseline(baseline),
         :ok <- validate_toolchains(toolchains),
         true <- gates == @gates,
         true <- decisions == @decisions do
      :ok
    else
      false -> {:error, :invalid_compatibility_review}
      {:error, _} = error -> error
    end
  end

  def validate(%{"schema_version" => version}),
    do: {:error, {:unsupported_compatibility_review, version}}

  def validate(_), do: {:error, :invalid_compatibility_review}

  @spec encode(map()) :: {:ok, binary()} | {:error, term()}
  def encode(review) do
    with :ok <- validate(review), do: Wotex.JSON.encode(review)
  end

  defp validate_api(
         %{
           "schema_version" => @api_schema,
           "package" => "wotex_lab",
           "version" => version,
           "compatibility_status" => "pre-1.0-review-baseline",
           "modules" => modules
         } = api
       )
       when is_list(modules) and modules != [] do
    with true <- map_size(api) == 5,
         true <- version?(version),
         true <- Enum.map(modules, & &1["module"]) == Enum.sort(Enum.map(modules, & &1["module"])),
         true <- unique?(Enum.map(modules, & &1["module"])),
         true <- Enum.all?(modules, &valid_module?/1) do
      :ok
    else
      false -> {:error, :invalid_api_baseline}
    end
  end

  defp validate_api(%{"schema_version" => version}),
    do: {:error, {:unsupported_api_baseline, version}}

  defp validate_api(_), do: {:error, :invalid_api_baseline}

  defp valid_module?(module) when is_map(module) and map_size(module) == 6 do
    name = module["module"]
    behaviours = module["behaviours"]
    struct_keys = module["struct_keys"]
    functions = module["functions"]
    specs = module["specs"]

    nonempty?(name) and valid_documentation?(module["documentation"]) and
      string_set?(behaviours) and string_set?(struct_keys) and is_list(functions) and
      unique?(Enum.map(functions, &{&1["name"], &1["arity"]})) and
      Enum.all?(functions, &valid_function?/1) and is_list(specs) and
      Enum.all?(specs, &valid_spec?/1)
  end

  defp valid_module?(_), do: false

  defp valid_function?(
         %{"name" => name, "arity" => arity, "documentation" => documentation} = value
       )
       when map_size(value) == 3,
       do:
         nonempty?(name) and is_integer(arity) and arity >= 0 and
           valid_documentation?(documentation)

  defp valid_function?(_), do: false

  defp valid_spec?(%{"name" => name, "arity" => arity, "contract" => contract} = value)
       when map_size(value) == 3,
       do: nonempty?(name) and is_integer(arity) and arity >= 0 and nonempty?(contract)

  defp valid_spec?(_), do: false

  defp valid_documentation?(%{"status" => status} = documentation)
       when status in @documentation_statuses do
    allowed =
      if status == "documented",
        do: ~w(status sha256 signatures defaults),
        else: ~w(status signatures defaults)

    Map.keys(documentation) -- allowed == [] and valid_doc_digest?(status, documentation) and
      valid_signatures?(documentation) and valid_defaults?(documentation)
  end

  defp valid_documentation?(_), do: false

  defp valid_doc_digest?("documented", %{"sha256" => digest}), do: digest?(digest)
  defp valid_doc_digest?("documented", _), do: false
  defp valid_doc_digest?(_, documentation), do: not Map.has_key?(documentation, "sha256")

  defp valid_signatures?(%{"signatures" => signatures}), do: string_list?(signatures)
  defp valid_signatures?(_), do: true

  defp valid_defaults?(%{"defaults" => defaults}), do: is_integer(defaults) and defaults > 0
  defp valid_defaults?(_), do: true

  defp baseline(api, digest) do
    modules = api["modules"]
    functions = Enum.flat_map(modules, & &1["functions"])
    specs = Enum.flat_map(modules, & &1["specs"])

    %{
      "path" => "priv/provenance/wotex-lab-api.json",
      "digest" => digest,
      "schema_version" => api["schema_version"],
      "modules" => length(modules),
      "exports" => length(functions),
      "typespec_clauses" => length(specs),
      "structs" => Enum.count(modules, &(not Enum.empty?(&1["struct_keys"]))),
      "behaviours" => Enum.count(modules, &(not Enum.empty?(&1["behaviours"]))),
      "module_documentation" => documentation_counts(Enum.map(modules, & &1["documentation"])),
      "export_documentation" => documentation_counts(Enum.map(functions, & &1["documentation"])),
      "documented_defaults" => Enum.count(functions, &Map.has_key?(&1["documentation"], "defaults"))
    }
  end

  defp validate_baseline(
         %{
           "path" => "priv/provenance/wotex-lab-api.json",
           "digest" => digest,
           "schema_version" => @api_schema,
           "modules" => modules,
           "exports" => exports,
           "typespec_clauses" => specs,
           "structs" => structs,
           "behaviours" => behaviours,
           "module_documentation" => module_docs,
           "export_documentation" => export_docs,
           "documented_defaults" => defaults
         } = baseline
       ) do
    counts = [modules, exports, specs, structs, behaviours, defaults]

    if map_size(baseline) == 11 and digest?(digest) and
         Enum.all?(counts, &(is_integer(&1) and &1 >= 0)) and
         valid_documentation_counts?(module_docs, modules) and
         valid_documentation_counts?(export_docs, exports),
       do: :ok,
       else: {:error, :invalid_compatibility_baseline}
  end

  defp validate_baseline(_), do: {:error, :invalid_compatibility_baseline}

  defp documentation_counts(values) do
    counts = Enum.frequencies_by(values, & &1["status"])
    Map.new(@documentation_statuses, &{&1, Map.get(counts, &1, 0)})
  end

  defp valid_documentation_counts?(counts, total) do
    is_map(counts) and Map.keys(counts) |> Enum.sort() == Enum.sort(@documentation_statuses) and
      Enum.all?(counts, fn {_, value} -> is_integer(value) and value >= 0 end) and
      Enum.sum(Map.values(counts)) == total
  end

  defp toolchains(%{"minimum" => minimum, "current" => current}) do
    values =
      [{"minimum", minimum}, {"current", current}]
      |> Enum.map(fn {lane, value} ->
        %{"lane" => lane, "elixir" => value["elixir"], "otp" => value["otp"]}
      end)

    if Enum.all?(values, &valid_toolchain?/1),
      do: {:ok, values},
      else: {:error, :invalid_toolchains}
  end

  defp toolchains(_), do: {:error, :invalid_toolchains}

  defp validate_toolchains(toolchains) when is_list(toolchains) do
    if Enum.map(toolchains, & &1["lane"]) == ~w(minimum current) and
         Enum.all?(toolchains, &valid_toolchain?/1),
       do: :ok,
       else: {:error, :invalid_compatibility_toolchains}
  end

  defp validate_toolchains(_), do: {:error, :invalid_compatibility_toolchains}

  defp valid_toolchain?(%{"lane" => lane, "elixir" => elixir, "otp" => otp} = value)
       when map_size(value) == 3,
       do: lane in ~w(minimum current) and nonempty?(elixir) and nonempty?(otp)

  defp valid_toolchain?(_), do: false

  defp digest?(value), do: is_binary(value) and Regex.match?(@digest, value)
  defp version?(value), do: is_binary(value) and Regex.match?(~r/\A\d+\.\d+\.\d+\z/, value)
  defp nonempty?(value), do: is_binary(value) and value != ""
  defp unique?(values), do: length(values) == length(Enum.uniq(values))
  defp string_list?(values), do: is_list(values) and Enum.all?(values, &is_binary/1)
  defp string_set?(values), do: string_list?(values) and values == Enum.sort(Enum.uniq(values))
end
