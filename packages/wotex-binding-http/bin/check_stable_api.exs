defmodule WotexBindingHTTP.Check.StableAPI do
  @moduledoc false

  @inventory "docs/stable-api-inventory.md"
  @test "test/wotex/binding/http/stable_api_inventory_test.exs"

  @cells for index <- 1..8,
             do:
               {"WBH-K#{String.pad_leading(Integer.to_string(index), 2, "0")}",
                [
                  "WBH-K#{String.pad_leading(Integer.to_string(index), 2, "0")}-P",
                  "WBH-K#{String.pad_leading(Integer.to_string(index), 2, "0")}-N"
                ]}

  @documented_functions %{
    Wotex.Binding.HTTP => ~w(config/1 empty_body/0 profile/0 transport/1),
    Wotex.Binding.HTTP.Config =>
      ~w(client/1 headers/1 instance_ref/1 max_event_bytes/1 max_header_bytes/1 max_header_count/1 max_request_bytes/1 max_response_bytes/1 max_uri_bytes/1 new/1),
    Wotex.Binding.HTTP.EmptyBody => ~w(new/0),
    Wotex.Binding.HTTP.Error => ~w(class/1),
    Wotex.Binding.HTTP.Headers => ~w(get/2 merge/2 new/2 put/3 token?/1),
    Wotex.Binding.HTTP.Notification => ~w(new/3),
    Wotex.Binding.HTTP.Request =>
      ~w(body/1 deadline/1 headers/1 max_event_bytes/1 max_header_bytes/1 max_header_count/1 max_response_bytes/1 max_uri_bytes/1 media_type/1 method/1 new/5 operation/1 request_id/1 stream?/1 uri/1),
    Wotex.Binding.HTTP.Response => ~w(body/1 headers/1 new/3 status/1),
    Wotex.Binding.HTTP.SSE.Event => ~w(data/1 event/1 id/1 new/2 retry/1),
    Wotex.Binding.HTTP.Transport => ~w(decode_frame/3)
  }

  @default_exports [
    {Wotex.Binding.HTTP.Headers, :new, 1},
    {Wotex.Binding.HTTP.SSE.Event, :new, 1}
  ]

  @runtime_callbacks [decode_frame: 3, request: 3, subscribe: 4, unsubscribe: 4]
  @client_callbacks [close: 2, request: 3, subscribe: 4]

  @spec main() :: :ok
  def main do
    result =
      try do
        verify!()
      catch
        :throw, {:violation, message} -> {:violation, message}
      end

    report(result)
  end

  defp verify! do
    inventory = File.read!(@inventory)
    test = File.read!(@test)

    verify_cells!(inventory, test)
    verify_public_functions!()
    verify_callbacks!()
    verify_error_manifest!(inventory)
    verify_package!()
    verify_policy!(inventory)
    :ok
  end

  defp verify_cells!(inventory, test) do
    rows =
      inventory
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "| WBH-K"))
      |> Enum.map(fn row ->
        [cell, _contract, vectors] = split_row(row)
        {cell, String.split(vectors, ", ")}
      end)

    exact!(rows, @cells, "stable API inventory cells")

    for {_cell, vectors} <- @cells, vector <- vectors do
      require!(test, "test \"#{vector}", "#{vector} has no executable compatibility vector")
    end
  end

  defp verify_public_functions! do
    Enum.each(@documented_functions, fn {module, expected} ->
      actual =
        case Code.fetch_docs(module) do
          {:docs_v1, _, _, _, _, _, docs} ->
            docs
            |> Enum.flat_map(fn
              {{:function, name, arity}, _, _, doc, _} when doc != :hidden ->
                ["#{name}/#{arity}"]

              _ ->
                []
            end)
            |> Enum.sort()

          _ ->
            violation("documentation metadata is unavailable for #{inspect(module)}")
        end

      exact!(actual, Enum.sort(expected), "documented functions for #{inspect(module)}")
    end)

    Enum.each(@default_exports, fn {module, name, arity} ->
      Code.ensure_loaded?(module) || violation("module is unavailable: #{inspect(module)}")

      unless function_exported?(module, name, arity) do
        violation("default-argument export #{inspect(module)}.#{name}/#{arity} is missing")
      end
    end)
  end

  defp verify_callbacks! do
    client = Wotex.Binding.HTTP.Client.behaviour_info(:callbacks) |> Enum.sort()
    exact!(client, @client_callbacks, "supplied-client callbacks")

    runtime = Wotex.Runtime.Transport.behaviour_info(:callbacks) |> Enum.sort()
    exact!(runtime, @runtime_callbacks, "Runtime transport callbacks")

    Code.ensure_loaded?(Wotex.Binding.HTTP.Transport) ||
      violation("HTTP Runtime transport module is unavailable")

    Enum.each(@runtime_callbacks, fn {name, arity} ->
      unless function_exported?(Wotex.Binding.HTTP.Transport, name, arity) do
        violation("HTTP Runtime transport omits #{name}/#{arity}")
      end
    end)
  end

  defp verify_error_manifest!(inventory) do
    source_codes =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn file ->
        ~r/(?:Error\.new|client_error)\(\s*(:[a-z_]+)/
        |> Regex.scan(File.read!(file), capture: :all_but_first)
        |> List.flatten()
      end)
      |> MapSet.new()

    manifest = section!(inventory, "<!-- error-manifest:start -->", "<!-- error-manifest:end -->")

    manifest_codes =
      manifest
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "| `:"))
      |> Enum.flat_map(fn row ->
        [codes | _] = split_row(row)
        Regex.scan(~r/`(:[a-z_]+)`/, codes, capture: :all_but_first) |> List.flatten()
      end)
      |> MapSet.new()

    exact!(manifest_codes, source_codes, "stable binding error code manifest")
  end

  defp verify_package! do
    project = Mix.Project.config()
    package_files = project |> Keyword.fetch!(:package) |> Keyword.fetch!(:files)
    docs_extras = project |> Keyword.fetch!(:docs) |> Keyword.fetch!(:extras) |> Keyword.keys()

    unless @inventory in package_files,
      do: violation("package allowlist omits the stable API inventory")

    unless String.to_atom(@inventory) in docs_extras,
      do: violation("generated documentation omits the stable API inventory")

    configuration = Code.eval_file(".check.exs") |> elem(0)
    tools = configuration |> Keyword.fetch!(:tools) |> Keyword.keys()

    unless :stable_api_candidate in tools,
      do: violation("default gate omits the stable API candidate check")
  end

  defp verify_policy!(inventory) do
    readme = File.read!("README.md")
    plan = File.read!("docs/plans/wotex-binding-http-completion.md")

    require!(readme, @inventory, "README does not link the stable API inventory")
    require!(plan, "stable_api_candidate", "completion plan omits the stable API gate")
    require!(inventory, "No rename", "migration decision is missing")
    require!(inventory, "future draft does not change", "draft revision decision is missing")
    require!(inventory, "does not establish a published", "release nonclaim is missing")

    for prior <- [
          "docs/http-operation-inventory.md",
          "docs/client-lifecycle-inventory.md",
          "docs/limits-security-inventory.md",
          "docs/reference-consumer-inventory.md",
          "docs/release-candidate-inventory.md"
        ] do
      unless File.regular?(prior), do: violation("preceding evidence is missing: #{prior}")
    end
  end

  defp split_row(row) do
    row
    |> String.split("|", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp section!(source, opening, closing) do
    with [_, rest] <- String.split(source, opening, parts: 2),
         [section, _] <- String.split(rest, closing, parts: 2) do
      section
    else
      _ -> violation("stable API error manifest markers are missing")
    end
  end

  defp exact!(actual, expected, label) do
    unless actual == expected do
      violation("#{label} is #{inspect(actual)}; expected #{inspect(expected)}")
    end
  end

  defp require!(source, value, message) do
    unless String.contains?(source, value), do: violation(message)
  end

  defp digest(path) do
    :sha256
    |> :crypto.hash(File.read!(path))
    |> Base.encode16(case: :lower)
  end

  defp violation(message), do: throw({:violation, message})

  defp report(:ok) do
    IO.puts("stable API compatibility vectors: WBH-K01..WBH-K08")
    IO.puts("binding error identities: 76")
    IO.puts("stable API inventory: sha256=#{digest(@inventory)}")
    IO.puts("published release, runtime matrix, and standards conformance: not claimed")
    :ok
  end

  defp report({:violation, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

WotexBindingHTTP.Check.StableAPI.main()
