defmodule Wotex.Modbus.ReleaseContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "WMB-C01 WMB-C10 package and project identities are exact" do
    project = Mix.Project.config()
    package = Keyword.fetch!(project, :package)

    assert project[:app] == :wotex_modbus
    assert project[:name] == "Wotex Modbus"
    assert project[:version] == "0.1.0"
    assert project[:elixir] == "~> 1.18"
    assert project[:source_url] == "https://github.com/wotex-project/wotex-modbus"
    assert project[:homepage_url] == "https://wotex.io"
    assert WotexModbus.MixProject.application() == [extra_applications: []]

    assert package[:name] == "wotex_modbus"
    assert package[:licenses] == ["Apache-2.0"]
    assert package[:maintainers] == ["Tobias Bohwalli <hi@futhr.io>"]

    assert package[:links] == %{
             "Changelog" => "https://github.com/wotex-project/wotex-modbus/blob/main/CHANGELOG.md",
             "Documentation" => "https://hexdocs.pm/wotex_modbus",
             "Project" => "https://wotex.io",
             "Source" => "https://github.com/wotex-project/wotex-modbus",
             "W3C Thing Description 1.1" =>
               "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/"
           }

    assert package[:files] ==
             ~w(.formatter.exs CHANGELOG.md CODE_OF_CONDUCT.md CONTRIBUTING.md GOVERNANCE.md LICENSE NOTICE README.md SECURITY.md docs/plans docs/provenance docs/specs lib mix.exs)
  end

  test "WMB-C01 exact supported API export inventory requires compatibility review" do
    assert exports(Wotex.Modbus) ==
             exports(
               capabilities: 0,
               connect: 1,
               disconnect: 1,
               health_check: 1,
               health_check: 2,
               profile: 0,
               profile: 1,
               read_coils: 3,
               read_discrete_inputs: 3,
               read_float: 2,
               read_holding_registers: 3,
               read_input_registers: 3,
               receive: 2,
               request: 2,
               send: 2,
               subscribe: 2,
               unsubscribe: 2,
               write_coil: 3,
               write_coils: 3,
               write_float: 3,
               write_holding_register: 3,
               write_holding_registers: 3
             )

    assert exports(Wotex.Modbus.Address) ==
             exports(__struct__: 0, __struct__: 1, new: 1, new: 2, new: 3)

    assert exports(Wotex.Modbus.Codec) == exports(decode: 1, encode: 2, response: 3)

    assert exports(Wotex.Modbus.Command) ==
             exports(__struct__: 0, __struct__: 1, new: 3, new: 4, validate: 1, write?: 1)

    assert exports(Wotex.Modbus.Connection) ==
             exports(
               child_spec: 1,
               close: 1,
               code_change: 3,
               config: 1,
               handle_call: 3,
               handle_cast: 2,
               handle_info: 2,
               init: 1,
               request: 3,
               start_link: 1,
               terminate: 2
             )

    assert exports(Wotex.Modbus.Error) ==
             exports(__struct__: 0, __struct__: 1, new: 1, new: 2, new: 3, with_effect: 2)

    assert exports(Wotex.Modbus.Mapping) ==
             exports(command: 2, command: 3, command: 4, decode: 2)

    assert exports(Wotex.Modbus.Session) ==
             exports(__struct__: 0, __struct__: 1, validate: 1)

    assert exports(Wotex.Modbus.Transport) ==
             exports(request: 3, subscribe: 4, unsubscribe: 4)

    assert exports(Wotex.Modbus.Value) ==
             exports(decode: 2, decode: 3, encode: 2, encode: 3)

    assert exports(Mix.Tasks.Wotex.Modbus.Software.Build) == exports(run: 1)
    assert exports(Mix.Tasks.Wotex.Modbus.Software.Run) == exports(run: 1)
  end

  defp exports(module) when is_atom(module), do: module.__info__(:functions) |> Enum.sort()
  defp exports(functions) when is_list(functions), do: Enum.sort(functions)
end
