defmodule Wotex.CoAP.Check.ApplicationFree do
  @moduledoc false

  @spec main() :: :ok
  def main do
    unless Application.spec(:wotex_coap, :mod) in [nil, [], :undefined] do
      System.halt(1)
    end

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    script = """
    nil = Process.whereis(:ssl_sup)
    {:ok, _} = Application.ensure_all_started(:wotex_coap)
    nil = Process.whereis(:ssl_sup)
    {:ok, value} = Wotex.CoAP.Security.new(mode: :dtls_psk, identity: "client", key: <<0::128>>)
    :ok = Wotex.CoAP.Security.validate(value)
    nil = Process.whereis(:ssl_sup)
    fixture = fn name -> File.read!("test/fixtures/dtls_pki/" <> name) end
    {:ok, pki} = Wotex.CoAP.Security.new(mode: :dtls_pki,
      trust_roots: [fixture.("root.der")], certificate: fixture.("client.der"),
      private_key: fixture.("client-key.der"), server_identity: {:dns, "fixture.test"},
      crls: [fixture.("valid-crl.der")])
    :ok = Wotex.CoAP.Security.validate(pki)
    nil = Process.whereis(:ssl_sup)
    IO.puts("explicit SSL startup passed")
    """

    {output, status} = System.cmd("elixir", paths ++ ["-e", script], stderr_to_stdout: true)
    IO.write(output)
    unless status == 0, do: System.halt(1)
    :ok
  end
end

Wotex.CoAP.Check.ApplicationFree.main()
