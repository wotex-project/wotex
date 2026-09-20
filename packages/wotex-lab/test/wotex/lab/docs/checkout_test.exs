defmodule Wotex.Lab.Docs.CheckoutTest do
  use ExUnit.Case, async: true

  alias Wotex.Lab.Docs.Checkout
  alias Wotex.Lab.Test.ChildEnvironment

  test "opens an exact clean detached checkout from a local qualification source" do
    {repository, revision} = fixture_repository()
    destination = temporary_path("checkout")
    on_exit(fn -> File.rm_rf!(destination) end)

    source = %{
      "repository_url" => "https://github.com/wotex-project/example",
      "revision" => revision
    }

    File.write!(Path.join(repository, "README.md"), "dirty\n")

    assert {:ok, ^destination} = Checkout.open(source, destination, repository: repository)
    assert File.read!(Path.join(destination, "README.md")) == "committed\n"
    assert String.trim(git!(destination, ["rev-parse", "HEAD"])) == revision
    assert String.trim(git!(destination, ["branch", "--show-current"])) == ""
  end

  test "refuses mutable, missing and occupied checkout inputs" do
    {repository, revision} = fixture_repository()

    source = %{
      "repository_url" => "https://github.com/wotex-project/example",
      "revision" => revision
    }

    occupied = temporary_path("occupied")
    on_exit(fn -> File.rm_rf!(occupied) end)
    File.mkdir!(occupied)
    File.write!(Path.join(occupied, "marker"), "keep")

    assert {:error, {:occupied_checkout_destination, ^occupied}} =
             Checkout.open(source, occupied, repository: repository)

    assert File.read!(Path.join(occupied, "marker")) == "keep"

    missing = %{source | "revision" => String.duplicate("f", 40)}
    destination = temporary_path("missing")
    on_exit(fn -> File.rm_rf!(destination) end)

    assert {:error, {:git_operation_failed, :checkout, _, _}} =
             Checkout.open(missing, destination, repository: repository)

    refute File.exists?(destination)

    assert {:error, {:invalid_checkout_origin, "git@example.invalid:repo"}} =
             Checkout.open(source, temporary_path("origin"), repository: "git@example.invalid:repo")
  end

  defp fixture_repository do
    root = temporary_path("repository")
    File.mkdir!(root)
    File.write!(Path.join(root, "README.md"), "committed\n")
    git!(root, ["init", "--quiet"])
    git!(root, ["config", "user.name", "Fixture"])
    git!(root, ["config", "user.email", "fixture@example.invalid"])
    git!(root, ["add", "README.md"])
    git!(root, ["commit", "--quiet", "-m", "fixture"])
    on_exit(fn -> File.rm_rf!(root) end)
    {root, git!(root, ["rev-parse", "HEAD"]) |> String.trim()}
  end

  defp git!(repository, args) do
    case System.cmd("git", ["-C", repository | args],
           stderr_to_stdout: true,
           env: ChildEnvironment.scrubbed()
         ) do
      {output, 0} -> output
      {output, status} -> flunk("git failed with #{status}: #{output}")
    end
  end

  defp temporary_path(name) do
    Path.join(System.tmp_dir!(), "wotex-doc-#{name}-#{token()}")
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
end
