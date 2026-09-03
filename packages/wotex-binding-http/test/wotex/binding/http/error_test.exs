defmodule Wotex.Binding.HTTP.ErrorTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.Binding.HTTP.{Error, Headers}

  test "error values expose stable fields and implement the Exception protocol" do
    error = Error.new(:client_request_failed, :client, "HTTP client request failed")

    assert %Error{
             code: :client_request_failed,
             phase: :client,
             message: "HTTP client request failed",
             details: %{}
           } = error

    assert Exception.message(error) == "HTTP client request failed"
  end

  test "safe diagnostic details remain available without changing the exception message" do
    error = Error.new(:http_status, :response, "HTTP status is not successful", %{status: 503})

    assert error.details == %{status: 503}
    assert Exception.message(error) == "HTTP status is not successful"
  end

  property "credential and framing field names are rejected without retaining their values" do
    forbidden =
      member_of([
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "connection",
        "content-length",
        "host",
        "keep-alive",
        "proxy-connection",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade"
      ])

    check all(
            name <- forbidden,
            suffix <- string(:alphanumeric, min_length: 1),
            casing <- member_of([:upcase, :downcase])
          ) do
      field_name = if casing == :upcase, do: String.upcase(name), else: name
      value = "secret-value:" <> suffix

      assert {:error, %Error{} = error} = Headers.new([{field_name, value}])
      refute error.message =~ value
      refute value in Map.values(error.details)
    end
  end

  property "control bytes in field values always produce normalized errors" do
    check all(byte <- member_of([127 | Enum.to_list(0..8) ++ Enum.to_list(10..31)])) do
      value = "safe" <> <<byte>> <> "tail"

      assert {:error,
              %Error{
                code: :invalid_header_value,
                phase: :request,
                details: %{name: "x-test"}
              }} = Headers.new([{"x-test", value}])
    end
  end
end
