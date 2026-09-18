defmodule WotexLabWorkbench.Test.GreptimeReceiver do
  @moduledoc false

  # One disposable pinned GreptimeDB standalone container for the separately
  # selected `WOTEX_LAB_GREPTIME=1` Workbench lane. It publishes only an
  # ephemeral IPv4-loopback HTTP port, keeps no named volume, carries CPU,
  # memory and PID budgets and is removed in `on_exit`. The image is never
  # pulled by the lane.

  alias WotexLabWorkbench.Test.ChildEnvironment

  @image "greptime/greptimedb:v1.1.4@sha256:9726587eac95d0360755254cd59a528dbf48abfdf268478aea6a644f62afe44c"

  @type t :: %{container: String.t(), base_url: String.t(), write_url: String.t()}

  @doc false
  @spec start() :: t()
  def start do
    container = "wotex-lab-greptime-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    ExUnit.Callbacks.on_exit(fn -> halt(container) end)

    {_, 0} =
      System.cmd(
        "docker",
        [
          "run",
          "--detach",
          "--pull",
          "never",
          "--name",
          container,
          "--label",
          "wotex-lab-lane=greptime",
          "--cpus",
          "2",
          "--memory",
          "1g",
          "--memory-swap",
          "1g",
          "--pids-limit",
          "512",
          "--publish",
          "127.0.0.1::4000",
          @image,
          "standalone",
          "start",
          "--http-addr",
          "0.0.0.0:4000"
        ],
        env: ChildEnvironment.scrubbed(),
        stderr_to_stdout: true
      )

    base_url = "http://127.0.0.1:#{mapped_port(container, 100)}"
    :ok = await(base_url <> "/health", 600)
    %{container: container, base_url: base_url, write_url: base_url <> "/v1/prometheus/write"}
  end

  @doc false
  @spec halt(String.t()) :: :ok
  def halt(container) do
    _ =
      System.cmd("docker", ["rm", "--force", "--volumes", container],
        env: ChildEnvironment.scrubbed(),
        stderr_to_stdout: true
      )

    :ok
  end

  defp mapped_port(container, 0), do: raise("#{container} published no mapped port")

  defp mapped_port(container, attempts) do
    with {output, 0} <-
           System.cmd("docker", ["port", container, "4000"],
             env: ChildEnvironment.scrubbed(),
             stderr_to_stdout: true
           ),
         [mapping | _] <- String.split(String.trim(output), "\n", trim: true) do
      mapping
      |> String.split(":")
      |> List.last()
      |> String.to_integer()
    else
      _ ->
        Process.sleep(100)
        mapped_port(container, attempts - 1)
    end
  end

  defp await(url, 0), do: raise("#{url} never became healthy")

  defp await(url, attempts) do
    case Req.get(url, retry: false, receive_timeout: 1_000) do
      {:ok, %{status: 200}} ->
        :ok

      _ ->
        Process.sleep(100)
        await(url, attempts - 1)
    end
  end
end
