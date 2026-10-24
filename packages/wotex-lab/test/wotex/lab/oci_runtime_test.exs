Code.require_file("../../../bin/support/oci_runtime.exs", __DIR__)

defmodule Wotex.Lab.OCIRuntimeTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Check.OCIRuntime

  @image "sha256:" <> String.duplicate("a", 64)
  @output "/tmp/wotex-oci-result"
  @mount "rw,noexec,nosuid,size=64m"

  test "the runtime lane requires an exact local image identity and explicit absolute output" do
    assert {:ok, %{image: @image, output: @output}} =
             OCIRuntime.parse(["--image", @image, "--output", @output])

    for image <- [
          "wotex:latest",
          "wotex@" <> @image,
          "SHA256:" <> String.duplicate("a", 64),
          "sha256:" <> String.duplicate("a", 63),
          @image <> "\n",
          "--privileged"
        ] do
      assert {:error, :invalid_options} =
               OCIRuntime.parse(["--image", image, "--output", @output])
    end

    for output <- ["relative", "/", "/tmp/../result", "", <<255>>, "/tmp/bad" <> <<0>>] do
      assert {:error, :invalid_options} =
               OCIRuntime.parse(["--image", @image, "--output", output])
    end
  end

  test "unknown, repeated, missing and malformed arguments never enter the runtime" do
    valid = ["--image", @image, "--output", @output]

    for arguments <- [
          nil,
          %{},
          [false],
          [],
          ["--image", @image],
          valid ++ ["--image", @image],
          ["--privileged" | valid],
          valid ++ ["--output", @output],
          ["other" | valid]
        ] do
      assert {:error, :invalid_options} = OCIRuntime.parse(arguments)
    end
  end

  test "inspection refuses every weakened runtime boundary independently" do
    container = %{
      "Image" => @image,
      "Config" => %{"User" => "65532:65532"},
      "HostConfig" => %{
        "ReadonlyRootfs" => true,
        "Memory" => 536_870_912,
        "NanoCpus" => 1_000_000_000,
        "PidsLimit" => 256,
        "CapDrop" => ["ALL"],
        "SecurityOpt" => ["no-new-privileges"],
        "Tmpfs" => %{"/tmp" => @mount, "/var/lib/wotex-lab" => @mount},
        "PortBindings" => %{"4000/tcp" => [%{"HostIp" => "127.0.0.1", "HostPort" => ""}]}
      }
    }

    assert OCIRuntime.runtime_policy?(container, @image)

    for {path, value} <- [
          {["Image"], "another-image"},
          {["Config", "User"], "root"},
          {["HostConfig", "ReadonlyRootfs"], false},
          {["HostConfig", "Memory"], 0},
          {["HostConfig", "NanoCpus"], 0},
          {["HostConfig", "PidsLimit"], 0},
          {["HostConfig", "CapDrop"], []},
          {["HostConfig", "SecurityOpt"], []},
          {["HostConfig", "Tmpfs"], %{}},
          {["HostConfig", "PortBindings"], %{"4000/tcp" => [%{"HostIp" => "0.0.0.0"}]}},
          {["HostConfig", "PortBindings"], %{"4000/tcp" => [%{"HostIp" => "::"}]}},
          {["HostConfig", "PortBindings"],
           %{"4000/tcp" => [%{"HostIp" => "127.0.0.1"}], "80/tcp" => []}}
        ] do
      refute OCIRuntime.runtime_policy?(put_in(container, path, value), @image), inspect(path)
    end

    refute OCIRuntime.runtime_policy?(%{}, @image)
  end
end
