defmodule Wotex.Matter.Descriptor do
  @moduledoc """
  Finite descriptor registry for the admitted Matter cluster recipes.

  Entries are keyed only by member kind, numeric cluster identifier, and
  numeric member identifier. They retain the pinned generated schema width,
  nullability, and admitted operations. Unknown paths fail explicitly and are
  never converted as generic JSON objects.

  The registry covers the P01 value recipes. P04 uses the matching generated
  C++ bindings for native SDK interactions.
  """

  alias Wotex.Matter.{Address, Error, TLV}

  @enforce_keys [:kind, :cluster, :member, :schema, :operations]
  defstruct [:kind, :cluster, :member, :schema, :operations]

  @type member_kind :: :attribute | :command | :event
  @type operation :: :read | :write | :invoke | :subscribe
  @type schema ::
          :nullable_i16
          | :i16
          | :u8
          | :boolean
          | :empty_structure
          | :device_type_list
          | :cluster_list
          | :parts_list
          | :reachable_event
  @type t :: %__MODULE__{
          kind: member_kind(),
          cluster: non_neg_integer(),
          member: non_neg_integer(),
          schema: schema(),
          operations: [operation()]
        }

  @entries [
    {:attribute, 0x0201, 0x0000, :nullable_i16, [:read, :subscribe]},
    {:attribute, 0x0201, 0x0011, :i16, [:read, :write]},
    {:attribute, 0x0201, 0x0012, :i16, [:read, :write]},
    {:attribute, 0x0201, 0x001C, :u8, [:read, :write]},
    {:attribute, 0x0006, 0x0000, :boolean, [:read, :subscribe]},
    {:command, 0x0006, 0x0000, :empty_structure, [:invoke]},
    {:command, 0x0006, 0x0001, :empty_structure, [:invoke]},
    {:command, 0x0006, 0x0002, :empty_structure, [:invoke]},
    {:attribute, 0x001D, 0x0000, :device_type_list, [:read]},
    {:attribute, 0x001D, 0x0001, :cluster_list, [:read]},
    {:attribute, 0x001D, 0x0002, :cluster_list, [:read]},
    {:attribute, 0x001D, 0x0003, :parts_list, [:read]},
    {:attribute, 0x0039, 0x0011, :boolean, [:read, :subscribe]},
    {:event, 0x0039, 0x0003, :reachable_event, [:read, :subscribe]},
    {:attribute, 0x0402, 0x0000, :nullable_i16, [:read, :subscribe]}
  ]

  @doc "Looks up an admitted descriptor by numeric path and member kind."
  @spec lookup(member_kind(), Address.t() | map(), operation()) ::
          {:ok, t()} | {:error, Error.t()}
  def lookup(kind, path, operation)
      when kind in [:attribute, :command, :event] and
             operation in [:read, :write, :invoke, :subscribe] do
    with {:ok, address} <- Address.new(path),
         {:ok, descriptor} <- find(kind, address.cluster, address.member),
         :ok <- admitted(descriptor, operation) do
      {:ok, descriptor}
    end
  end

  def lookup(_, _, _), do: {:error, Error.new(:unsupported_schema)}

  @doc "Converts a pinned generated-schema value to one anonymous TLV element."
  @spec to_element(member_kind(), Address.t() | map(), operation(), term()) ::
          {:ok, TLV.element()} | {:error, Error.t()}
  def to_element(kind, path, operation, native_value) do
    with {:ok, descriptor} <- lookup(kind, path, operation),
         {:ok, element} <- convert(descriptor.schema, native_value),
         {:ok, element} <- TLV.validate_element(element) do
      {:ok, element}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_value)}
    end
  end

  @doc "Validates a caller-supplied TLV element against its admitted descriptor."
  @spec validate_element(member_kind(), Address.t() | map(), operation(), term()) ::
          {:ok, TLV.element()} | {:error, Error.t()}
  def validate_element(kind, path, operation, element) do
    with {:ok, descriptor} <- lookup(kind, path, operation),
         {:ok, normalized} <- TLV.validate_element(element),
         true <- schema_matches?(descriptor.schema, normalized) do
      {:ok, normalized}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_value)}
    end
  end

  @doc "Converts one validated descriptor element to its schema value."
  @spec from_element(member_kind(), Address.t() | map(), operation(), term()) ::
          {:ok, term()} | {:error, Error.t()}
  def from_element(kind, path, operation, element) do
    with {:ok, descriptor} <- lookup(kind, path, operation),
         {:ok, normalized} <- validate_element(kind, path, operation, element),
         {:ok, value} <- extract(descriptor.schema, normalized) do
      {:ok, value}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_value)}
    end
  end

  defp find(kind, cluster, member) do
    case Enum.find(@entries, fn {k, c, m, _, _} -> {k, c, m} == {kind, cluster, member} end) do
      {^kind, ^cluster, ^member, schema, operations} ->
        {:ok,
         %__MODULE__{
           kind: kind,
           cluster: cluster,
           member: member,
           schema: schema,
           operations: operations
         }}

      nil ->
        {:error, Error.new(:unsupported_schema)}
    end
  end

  defp admitted(%__MODULE__{operations: operations}, operation) do
    cond do
      operation in operations -> :ok
      operation == :write -> {:error, Error.new(:not_writable)}
      true -> {:error, Error.new(:unsupported_operation)}
    end
  end

  defp convert(:nullable_i16, nil), do: element(:null, nil)
  defp convert(:nullable_i16, value), do: convert(:i16, value)

  defp convert(:i16, value) when is_integer(value) and value in -32_768..32_767,
    do: element(:i16, value)

  defp convert(:u8, value) when is_integer(value) and value in 0..255, do: element(:u8, value)
  defp convert(:boolean, value) when is_boolean(value), do: element(:boolean, value)
  defp convert(:empty_structure, value) when value == %{}, do: element(:structure, [])

  defp convert(:cluster_list, values) when is_list(values) do
    array(values, fn value ->
      if valid_cluster?(value), do: scalar(:u32, value, 0..0xFFFFFFFF), else: :error
    end)
  end

  defp convert(:parts_list, values) when is_list(values) do
    array(values, fn value -> scalar(:u16, value, 0..0xFFFE) end)
  end

  defp convert(:device_type_list, values) when is_list(values) do
    array(values, fn
      %{device_type: device_type, revision: revision} = entry when map_size(entry) == 2 ->
        with {:ok, device_type} <- tagged_scalar({:context, 0}, :u32, device_type, 0..0xFFFFFFFF),
             {:ok, revision} <- tagged_scalar({:context, 1}, :u16, revision, 0..0xFFFF) do
          {:ok, %{tag: :anonymous, type: :structure, value: [device_type, revision]}}
        end

      _ ->
        :error
    end)
  end

  defp convert(:reachable_event, %{reachable: value} = event) when map_size(event) == 1 do
    with {:ok, child} <- tagged_scalar({:context, 0}, :boolean, value, :boolean) do
      element(:structure, [child])
    end
  end

  defp convert(_, _), do: :error

  defp array(values, converter) when length(values) <= 1023 do
    with {:ok, children} <- traverse(values, converter, []) do
      element(:array, children)
    end
  end

  defp array(_, _), do: :error

  defp traverse([], _, acc), do: {:ok, Enum.reverse(acc)}

  defp traverse([value | rest], converter, acc) do
    case converter.(value) do
      {:ok, child} -> traverse(rest, converter, [child | acc])
      _ -> :error
    end
  end

  defp scalar(type, value, range), do: tagged_scalar(:anonymous, type, value, range)

  defp tagged_scalar(tag, :boolean, value, :boolean) when is_boolean(value),
    do: {:ok, %{tag: tag, type: :boolean, value: value}}

  defp tagged_scalar(tag, type, value, first..last//1)
       when is_integer(value) and value >= first and value <= last,
       do: {:ok, %{tag: tag, type: type, value: value}}

  defp tagged_scalar(_, _, _, _), do: :error
  defp element(type, value), do: {:ok, %{tag: :anonymous, type: type, value: value}}

  defp schema_matches?(:nullable_i16, %{tag: :anonymous, type: :null, value: nil}), do: true
  defp schema_matches?(:nullable_i16, element), do: schema_matches?(:i16, element)

  defp schema_matches?(:i16, %{tag: :anonymous, type: :i16, value: value}),
    do: value in -32_768..32_767

  defp schema_matches?(:u8, %{tag: :anonymous, type: :u8, value: value}),
    do: value in 0..255

  defp schema_matches?(:boolean, %{tag: :anonymous, type: :boolean, value: value}),
    do: is_boolean(value)

  defp schema_matches?(:empty_structure, %{tag: :anonymous, type: :structure, value: []}),
    do: true

  defp schema_matches?(:cluster_list, %{tag: :anonymous, type: :array, value: values}) do
    Enum.all?(values, fn
      %{tag: :anonymous, type: :u32, value: value} -> valid_cluster?(value)
      _ -> false
    end)
  end

  defp schema_matches?(:parts_list, %{tag: :anonymous, type: :array, value: values}),
    do: Enum.all?(values, &match?(%{tag: :anonymous, type: :u16}, &1))

  defp schema_matches?(:device_type_list, %{tag: :anonymous, type: :array, value: values}) do
    Enum.all?(values, fn
      %{
        tag: :anonymous,
        type: :structure,
        value: [
          %{tag: {:context, 0}, type: :u32},
          %{tag: {:context, 1}, type: :u16}
        ]
      } ->
        true

      _ ->
        false
    end)
  end

  defp schema_matches?(:reachable_event, %{
         tag: :anonymous,
         type: :structure,
         value: [%{tag: {:context, 0}, type: :boolean, value: value}]
       }),
       do: is_boolean(value)

  defp schema_matches?(_, _), do: false

  defp valid_cluster?(value),
    do:
      value in 0..0x7FFF or
        (value in 0x00010000..0xFFF47FFF and rem(value, 65_536) <= 0x7FFF)

  defp extract(:nullable_i16, %{type: :null}), do: {:ok, nil}

  defp extract(schema, %{value: value}) when schema in [:nullable_i16, :i16, :u8, :boolean],
    do: {:ok, value}

  defp extract(:empty_structure, %{type: :structure, value: []}), do: {:ok, %{}}

  defp extract(:cluster_list, %{value: values}),
    do: {:ok, Enum.map(values, & &1.value)}

  defp extract(:parts_list, %{value: values}),
    do: {:ok, Enum.map(values, & &1.value)}

  defp extract(:device_type_list, %{value: values}) do
    {:ok,
     Enum.map(values, fn %{value: [device_type, revision]} ->
       %{device_type: device_type.value, revision: revision.value}
     end)}
  end

  defp extract(:reachable_event, %{value: [%{value: reachable}]}),
    do: {:ok, %{reachable: reachable}}

  defp extract(_, _), do: :error
end
