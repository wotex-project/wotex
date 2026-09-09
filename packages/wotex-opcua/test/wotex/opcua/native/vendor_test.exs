defmodule Wotex.OPCUA.Native.VendorTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Native.Vendor

  setup do
    directory =
      Path.join(System.tmp_dir!(), "wotex-opcua-vendor-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    File.cp_r!(
      Application.app_dir(:wotex_opcua, "priv/native/vendor"),
      Path.join(directory, "vendor")
    )

    %{directory: directory}
  end

  test "WOP-X01 reviewed parser and MIT notice have exact pinned bytes", context do
    assert Vendor.verify(context.directory) == :ok
  end

  test "WOP-X01 missing, substituted and symbolic vendor files fail before build", context do
    path = Path.join(context.directory, "vendor/yyjson/LICENSE")
    original = File.read!(path)
    File.write!(path, :binary.copy("x", byte_size(original)))
    assert Vendor.verify(context.directory) == {:error, :native_vendor_digest_mismatch}
    File.rm!(path)
    assert Vendor.verify(context.directory) == {:error, :native_vendor_digest_mismatch}
    source = Path.join(context.directory, "license-source")
    File.write!(source, original)
    File.ln_s!(source, path)
    assert Vendor.verify(context.directory) == {:error, :native_vendor_digest_mismatch}
  end

  test "WOP-X01 malformed and absent directories are finite source-admission failures" do
    for path <- [nil, [], %{}, "relative", "/" <> <<0>>, <<255>>, "/absent/vendor-directory"] do
      assert Vendor.verify(path) == {:error, :native_vendor_digest_mismatch}
    end
  end
end
