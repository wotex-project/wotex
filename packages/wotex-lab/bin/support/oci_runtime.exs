defmodule Wotex.Lab.Check.OCIRuntime do
  @moduledoc false

  @image ~r/\Asha256:[a-f0-9]{64}\z/
  @mount "rw,noexec,nosuid,size=64m"

  @spec parse(term()) :: {:ok, %{image: String.t(), output: Path.t()}} | {:error, :invalid_options}
  def parse(arguments) when is_list(arguments) do
    if Enum.all?(arguments, &is_binary/1) do
      {options, rest, invalid} =
        OptionParser.parse(arguments, strict: [image: :keep, output: :keep])

      image = Keyword.get(options, :image)
      output = Keyword.get(options, :output)

      if rest == [] and invalid == [] and length(options) == 2 and
           is_binary(image) and Regex.match?(@image, image) and valid_output?(output) do
        {:ok, %{image: image, output: output}}
      else
        {:error, :invalid_options}
      end
    else
      {:error, :invalid_options}
    end
  end

  def parse(_), do: {:error, :invalid_options}

  defp valid_output?(output) when is_binary(output) do
    byte_size(output) <= 4_096 and String.valid?(output) and
      not String.contains?(output, <<0>>) and Path.type(output) == :absolute and
      Path.expand(output) == output and output != "/"
  end

  defp valid_output?(_), do: false

  @spec arguments(String.t(), String.t()) :: [String.t()]
  def arguments(image, name) do
    [
      "run",
      "--detach",
      "--pull",
      "never",
      "--name",
      name,
      "--read-only",
      "--tmpfs",
      "/tmp:" <> @mount,
      "--tmpfs",
      "/var/lib/wotex-lab:" <> @mount,
      "--memory",
      "512m",
      "--cpus",
      "1",
      "--pids-limit",
      "256",
      "--cap-drop",
      "ALL",
      "--security-opt",
      "no-new-privileges",
      "--publish",
      "127.0.0.1::4000",
      "--env",
      "SECRET_KEY_BASE",
      "--env",
      "PHX_HOST=localhost",
      image
    ]
  end

  @spec runtime_policy?(map(), String.t()) :: boolean()
  def runtime_policy?(
        %{
          "Image" => image,
          "Config" => %{"User" => "65532:65532"},
          "HostConfig" => %{
            "ReadonlyRootfs" => true,
            "Memory" => 536_870_912,
            "NanoCpus" => 1_000_000_000,
            "PidsLimit" => 256,
            "CapDrop" => ["ALL"],
            "SecurityOpt" => ["no-new-privileges"],
            "Tmpfs" => %{"/tmp" => @mount, "/var/lib/wotex-lab" => @mount} = mounts,
            "PortBindings" => bindings
          }
        },
        image
      ),
      do: map_size(mounts) == 2 and loopback_binding?(bindings)

  def runtime_policy?(_, _), do: false

  defp loopback_binding?(%{"4000/tcp" => [%{"HostIp" => "127.0.0.1"}]} = bindings),
    do: map_size(bindings) == 1

  defp loopback_binding?(_), do: false
end
