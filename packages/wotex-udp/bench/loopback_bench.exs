alias Wotex.UDP
alias Wotex.UDP.{Config, Endpoint}

{:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
{:ok, config} = Config.new(local: local)
{:ok, socket} = UDP.open(config)
{:ok, destination} = UDP.local(socket)

try do
  Benchee.run(
    %{
      "send and receive a complete loopback datagram" => fn payload ->
        :ok = UDP.send(socket, destination, payload, 1_000)
        {:ok, %{data: ^payload}} = UDP.recv(socket, 1_000)
      end
    },
    inputs: [bytes_64: :binary.copy(<<1>>, 64), bytes_1472: :binary.copy(<<2>>, 1_472)],
    warmup: 1,
    time: 3,
    memory_time: 1,
    formatters: [
      Benchee.Formatters.Console,
      {Benchee.Formatters.Markdown,
       file: "bench/output/loopback.md",
       title: "# UDP loopback datagrams",
       description: "Complete send and receive through a caller-owned IPv4 loopback socket."}
    ]
  )
after
  UDP.close(socket)
end
