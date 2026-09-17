defmodule Wotex.BLE.NativeProcesses do
  @moduledoc false

  # Operating-system process observations for native ownership tests. Linux
  # uses /proc; other hosts use ps. Zombies count as released processes.

  @spec children(pos_integer()) :: [pos_integer()]
  def children(parent) do
    case File.ls("/proc") do
      {:ok, names} ->
        for name <- names,
            {pid, ""} <- [Integer.parse(name)],
            match?({^parent, _}, stat(pid)),
            do: pid

      _ ->
        for line <- String.split(ps(["-A", "-o", "pid=", "-o", "ppid="]), "\n", trim: true),
            [pid, ppid] <- [String.split(line)],
            String.to_integer(ppid) == parent,
            do: String.to_integer(pid)
    end
  end

  @spec alive?(pos_integer()) :: boolean()
  def alive?(pid) do
    if File.dir?("/proc") do
      match?({_, state} when state != "Z", stat(pid))
    else
      state = String.trim(ps(["-o", "stat=", "-p", Integer.to_string(pid)]))
      state != "" and not String.starts_with?(state, "Z")
    end
  end

  # The parenthesized command in /proc/PID/stat may contain spaces or parentheses.
  defp stat(pid) do
    with {:ok, bytes} <- File.read("/proc/#{pid}/stat"),
         [_, fields] <- Regex.run(~r/\A.*\)\s(.*)\z/s, bytes),
         [state, parent | _] <- String.split(fields) do
      {String.to_integer(parent), state}
    else
      _ -> nil
    end
  end

  defp ps(arguments) do
    {output, _} =
      System.cmd("ps", arguments,
        stderr_to_stdout: true,
        env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
      )

    output
  end
end
