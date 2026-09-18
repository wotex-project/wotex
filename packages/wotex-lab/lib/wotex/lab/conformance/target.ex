defmodule Wotex.Lab.Conformance.Target do
  @moduledoc """
  An external conformance target that exposes the core package as a subject.

  The target implements the `wotex_conformance` external protocol from its
  public documentation: it reads one canonical JSON request from standard
  input, derives one normalized observation by running the declared document
  through `Wotex.ThingDescription` or `Wotex.ThingModel`, applies the declared
  projection, writes one JSON response, and exits. It never imports runner
  internals, never receives expectations, and reports operations it does not
  implement as `unsupported`.

  `respond/1` is the pure core so the same derivation is testable in-process;
  `main/1` is the operating-system entry used through a port by the runner,
  and `serve/2` is its exchange over any I/O device.
  This is independent consumer evidence about the core package, not an
  independent WoT parser.
  """

  alias Wotex.{JSON, ThingDescription, ThingModel}
  alias Wotex.Lab.Telemetry

  @protocol "wotex.conformance.target"
  @protocol_version "1.0"
  @operations %{
    "thing_description.parse" => {ThingDescription, :parse},
    "thing_description.validate" => {ThingDescription, :validate},
    "thing_model.parse" => {ThingModel, :parse},
    "thing_model.validate" => {ThingModel, :validate}
  }

  @doc "Derives the protocol response for one decoded request."
  @spec respond(map()) :: map()
  def respond(%{"vector" => %{"id" => vector_id}} = request) when is_binary(vector_id) do
    operation = get_in(request, ["claim", "operation"])
    input = get_in(request, ["vector", "input"]) || %{}

    case Map.fetch(@operations, operation) do
      {:ok, {module, mode}} ->
        Telemetry.span(:conformance, :conformance, %{operation: operation}, fn ->
          base(vector_id, "observed")
          |> Map.put(
            "actual",
            observe(module, mode, Map.get(input, "document"), Map.get(input, "projection", []))
          )
          |> Map.put("codes", [])
        end)

      :error ->
        base(vector_id, "unsupported") |> Map.put("codes", ["operation_not_implemented"])
    end
  end

  def respond(_), do: base("unknown", "unsupported") |> Map.put("codes", ["invalid_request"])

  @doc """
  Runs the target as an operating-system process: `--archive <path>` then one request line on stdin.

  Standard I/O is switched to binary mode and served by `serve/2`; the node
  halts with the status it returns. The UTF-8 request and response pass
  through unchanged whatever locale the host selects.
  """
  @spec main([String.t()]) :: no_return()
  def main(args) do
    :ok = :io.setopts(:standard_io, binary: true)
    System.halt(serve(args, :standard_io))
  end

  @doc """
  Serves one request line from a binary-mode I/O `device` and writes the response to it.

  Returns the exit status `main/1` halts with: 0 after a response, otherwise
  the `run/2` failure code. The line is read and the response written in the
  encoding `device` already has rather than a switched one: before OTP 28 a
  `-noshell` node decodes standard input as soon as it arrives, with the
  encoding the locale selected at boot, so a switch made here would not reach
  a request the runner wrote before the target read it. A Latin-1 device maps
  each byte to one character and a Unicode device decodes valid UTF-8
  losslessly, so reading and writing in the device's encoding returns the
  original bytes. A Unicode device that meets invalid UTF-8 falls back to
  Latin-1; such a request is undecodable.
  """
  @spec serve([String.t()], IO.device()) :: 0 | 11..14
  def serve(args, device) do
    unicode? = unicode?(device)

    case run(args, fn -> read_line(device, unicode?) end) do
      {:ok, encoded} ->
        if unicode?,
          do: IO.write(device, encoded <> "\n"),
          else: IO.binwrite(device, encoded <> "\n")

        0

      {:error, code} ->
        code
    end
  end

  @doc """
  Performs one target exchange without touching the operating system process.

  `read_line` supplies the request line, `:eof` or `{:error, reason}`.
  Failures map to the documented exit codes: 11 missing archive argument,
  12 unreadable archive, 13 end of input, 14 undecodable request, including
  `{:error, :invalid_utf8}` for input that is not UTF-8.
  """
  @spec run([String.t()], (-> binary() | :eof | {:error, term()})) ::
          {:ok, binary()} | {:error, 11..14}
  def run(args, read_line) when is_function(read_line, 0) do
    with {:ok, _} <- archive(args),
         {:ok, request} <- read_request(read_line.()) do
      JSON.encode(respond(request))
    end
  end

  defp archive(["--archive", path]) do
    if File.regular?(path), do: {:ok, path}, else: {:error, 12}
  end

  defp archive(_), do: {:error, 11}

  defp unicode?(device) do
    case :io.getopts(device) do
      options when is_list(options) -> :proplists.get_value(:encoding, options) in [:unicode, :utf8]
      _ -> false
    end
  end

  defp read_line(device, false), do: IO.binread(device, :line)

  defp read_line(device, true) do
    line = IO.read(device, :line)
    if unicode?(device), do: line, else: {:error, :invalid_utf8}
  end

  defp read_request(line) when is_binary(line) do
    case JSON.decode(line) do
      {:ok, request} when is_map(request) -> {:ok, request}
      _ -> {:error, 14}
    end
  end

  defp read_request({:error, :invalid_utf8}), do: {:error, 14}

  defp read_request(_), do: {:error, 13}

  defp observe(module, mode, document, projection) when is_map(document) do
    result =
      case mode do
        :parse ->
          case JSON.encode(document) do
            {:ok, json} -> module.parse(json)
            {:error, error} -> {:error, [error]}
          end

        :validate ->
          module.from_map(document)
      end

    case result do
      {:ok, value} ->
        accepted = module.to_map(value)
        %{"accepted" => true, "document" => project(accepted, projection)}

      {:error, errors} ->
        %{"accepted" => false, "errors" => normalize_errors(errors)}
    end
  end

  defp observe(_, _, _, _) do
    %{
      "accepted" => false,
      "errors" => [%{"code" => "object_required", "phase" => "value", "path" => "/"}]
    }
  end

  defp project(document, []), do: document

  defp project(document, pointers) when is_list(pointers) do
    Enum.reduce(pointers, %{}, fn pointer, acc ->
      case JSON.resolve_pointer(document, pointer) do
        {:ok, value} -> Map.put(acc, pointer, value)
        :error -> acc
      end
    end)
  end

  defp normalize_errors(errors) do
    errors
    |> List.wrap()
    |> Enum.map(fn %{code: code, phase: phase} = error ->
      %{
        "code" => Atom.to_string(code),
        "phase" => Atom.to_string(phase),
        "path" => Map.get(error, :path) || "/"
      }
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1["path"], &1["code"]})
  end

  defp base(vector_id, outcome) do
    %{
      "protocol" => @protocol,
      "protocol_version" => @protocol_version,
      "vector_id" => vector_id,
      "outcome" => outcome
    }
  end
end
