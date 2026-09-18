defmodule Wotex.Thread.Bench.Datasets do
  @moduledoc false

  # Synthetic Operational Datasets: a complete Active Dataset, a complete
  # Pending Dataset and an Active Dataset padded with unknown TLVs to the
  # 254-byte limit. Key material is a fixed test pattern.

  @active [
    {14, <<0, 0, 0, 0, 0, 1, 0, 0>>},
    {0, <<0, 0, 15>>},
    {53, <<0, 4, 0x00, 0x1F, 0xFF, 0xE0>>},
    {2, <<0xDE, 0xAD, 0x00, 0xBE, 0xEF, 0x00, 0xCA, 0xFE>>},
    {7, <<0xFD, 0x00, 0x0D, 0xB8, 0x00, 0x00, 0x00, 0x00>>},
    {5, :binary.copy(<<0x00, 0x11, 0x22, 0x33>>, 4)},
    {1, <<0x12, 0x34>>},
    {3, "wotex-bench"},
    {4, :binary.copy(<<0x44, 0x55, 0x66, 0x77>>, 4)},
    {12, <<0x02, 0xA0, 0xF7, 0xF8>>}
  ]

  @pending_only [{51, <<0, 0, 0, 0, 0, 2, 0, 0>>}, {52, <<0, 0, 0x75, 0x30>>}]

  @spec inputs() :: %{String.t() => map()}
  def inputs do
    padding = Enum.map(128..135, &{&1, :binary.copy(<<&1>>, if(&1 == 135, do: 10, else: 18))})

    %{
      "Active Dataset (10 TLVs)" => input(@active, :active),
      "Pending Dataset (12 TLVs)" => input(@active ++ @pending_only, :pending),
      "254 bytes with 8 unknown TLVs" => input(@active ++ padding, :active)
    }
  end

  defp input(entries, context) do
    bytes = for {type, value} <- entries, into: <<>>, do: <<type, byte_size(value), value::binary>>
    {:ok, dataset} = Wotex.Thread.Dataset.decode(bytes)
    %{bytes: bytes, dataset: dataset, context: context}
  end
end
