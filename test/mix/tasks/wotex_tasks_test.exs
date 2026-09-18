defmodule Mix.Tasks.WotexTasksTest do
  @moduledoc false

  use ExUnit.Case, async: true

  defp tasks do
    {:ok, modules} = :application.get_key(:wotex_workspace, :modules)

    for module <- modules,
        String.starts_with?(Atom.to_string(module), "Elixir.Mix.Tasks.Wotex."),
        do: module
  end

  test "every wotex task has a shortdoc and a moduledoc" do
    assert tasks() != []

    for module <- tasks() do
      assert is_binary(Mix.Task.shortdoc(module)), "#{inspect(module)} has no shortdoc"
      assert is_binary(Mix.Task.moduledoc(module)), "#{inspect(module)} has no moduledoc"
    end
  end

  test "the root aliases are the design's command set and name existing tasks" do
    aliases = Mix.Project.config()[:aliases]

    assert Enum.sort(Enum.map(Keyword.keys(aliases), &Atom.to_string/1)) ==
             Enum.sort(~w(setup affected pkg def refs impact test.affected check.fast
                          check.affected check.all workspace format.all lint dialyzer.pkg
                          docs.check docs.pkg index native.build native.sources
                          native.advisories native.lint native.test check))

    for {name, tasks} <- aliases, task <- List.wrap(tasks) do
      [task_name | _] = String.split(task)
      assert Mix.Task.get(task_name), "alias #{name}: task #{task_name} not found"
    end

    # Mix appends alias arguments to the last task: it must be a wotex task.
    for {name, tasks} <- aliases do
      assert String.starts_with?(List.last(List.wrap(tasks)), "wotex."),
             "alias #{name} must end in a wotex.* task"
    end
  end
end
