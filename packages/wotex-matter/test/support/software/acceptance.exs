Code.require_file("manifest.exs", __DIR__)
Code.require_file("case_formatter.exs", __DIR__)

defmodule Wotex.Matter.SoftwareAcceptance do
  @moduledoc false

  import Bitwise

  alias Wotex.Matter.{SoftwareCaseFormatter, SoftwareManifest}

  @spec configure!(String.t(), map()) :: :ok
  def configure!(root, environment) do
    unless environment["WOTEX_REQUIRE_SOFTWARE"] == "1", do: fail(:invalid_software_requirement)
    path = Path.join(root, "test/support/software/acceptance.json")
    inventory = inventory!(path)
    Enum.each(inventory["environment"], &fixture!(&1, environment))

    for item <- inventory["cases"] do
      source = Path.join(root, item["file"])
      SoftwareManifest.assert_directories!(Path.dirname(source))
      SoftwareManifest.digest(source)
    end

    result = environment["WOTEX_SOFTWARE_RESULT_PATH"]
    absolute!(result)
    unless File.lstat(result) == {:error, :enoent}, do: fail(:software_result_exists)

    context = %{
      root: root,
      cases: inventory["cases"],
      result: result,
      source_sha256: SoftwareManifest.identity(root)["source_sha256"],
      inventory_sha256: SoftwareManifest.digest(path)
    }

    formatters = List.insert_at(ExUnit.configuration()[:formatters], -1, SoftwareCaseFormatter)
    ExUnit.configure(formatters: Enum.uniq(formatters), software_acceptance: context)
    ExUnit.after_suite(fn statistics -> verify_result!(context, statistics) end)
    :ok
  end

  @spec inventory!(String.t()) :: map()
  def inventory!(path) do
    inventory = SoftwareManifest.read(path)

    unless valid_inventory_shape?(inventory),
      do: fail(:invalid_software_inventory)

    identities =
      for item <- inventory["cases"] do
        unless valid_case?(item),
          do: fail(:invalid_software_inventory)

        {item["module"], item["name"]}
      end

    unless length(Enum.uniq(identities)) == length(identities),
      do: fail(:invalid_software_inventory)

    for {name, kind} <- inventory["environment"] do
      unless valid_environment_entry?(name, kind),
        do: fail(:invalid_software_inventory)
    end

    inventory
  end

  defp valid_inventory_shape?(inventory) do
    match?(%{"schema" => "wotex.matter.software-cases@1"}, inventory) and
      Enum.sort(Map.keys(inventory)) == ["cases", "environment", "schema"] and
      is_list(inventory["cases"]) and length(inventory["cases"]) in 1..256 and
      is_map(inventory["environment"]) and map_size(inventory["environment"]) <= 64
  end

  defp valid_case?(item) do
    is_map(item) and Enum.sort(Map.keys(item)) == ["evidence", "file", "module", "name"] and
      valid_file?(item["file"]) and valid_text?(item["module"], 256) and
      valid_text?(item["name"], 512) and item["evidence"] in ["shared-sdk", "native-contract"]
  end

  defp valid_environment_entry?(name, kind),
    do: Regex.match?(~r/\AWOTEX_[A-Z_]+\z/, name) and kind in ["fixture", "executable"]

  defp fixture!({name, kind}, environment) do
    path = environment[name]
    absolute!(path)

    case {kind, File.lstat(path)} do
      {"fixture", {:ok, %{type: :regular, size: size, mode: mode}}}
      when size in 1..131_072 and (mode &&& 0o077) == 0 ->
        case Wotex.JSON.decode(File.read!(path), max_bytes: 131_072) do
          {:ok, value} when is_map(value) -> :ok
          _ -> fail(:invalid_software_fixture)
        end

      {"executable", {:ok, %{type: :regular, mode: mode}}} when (mode &&& 0o111) != 0 ->
        :ok

      _ ->
        fail(:invalid_software_fixture)
    end
  end

  defp absolute!(path) do
    unless valid_text?(path, 4096) and Path.type(path) == :absolute and
             Enum.all?(Path.split(path), &(&1 not in [".", ".."])),
           do: fail(:invalid_software_path)

    SoftwareManifest.assert_directories!(Path.dirname(path))
  end

  defp valid_file?(path) do
    valid_text?(path, 4096) and Path.type(path) == :relative and
      String.starts_with?(path, "test/") and String.ends_with?(path, ".exs") and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."]))
  end

  defp valid_text?(value, limit),
    do:
      is_binary(value) and byte_size(value) in 1..limit and String.valid?(value) and
        not String.contains?(value, [<<0>>, "\n", "\r", "\\"])

  defp verify_result!(context, statistics) do
    result = SoftwareManifest.read(context.result)

    unless result["schema"] == "wotex.matter.software-results@1" and
             result["status"] == "passed" and
             result["source_sha256"] == context.source_sha256 and
             result["inventory_sha256"] == context.inventory_sha256 and
             statistics.failures == 0,
           do: fail(:software_acceptance_failed)
  end

  defp fail(reason), do: Mix.raise(Atom.to_string(reason))
end
