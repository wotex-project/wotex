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
          | :access_control_list
          | :window_status
          | :nullable_fabric_index
          | :nullable_vendor_id
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
    {:attribute, 0x0402, 0x0000, :nullable_i16, [:read, :subscribe]},
    {:attribute, 0x001F, 0x0000, :access_control_list, [:read, :write]},
    {:attribute, 0x003C, 0x0000, :window_status, [:read]},
    {:attribute, 0x003C, 0x0001, :nullable_fabric_index, [:read]},
    {:attribute, 0x003C, 0x0002, :nullable_vendor_id, [:read]}
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
         true <- schema_matches?(descriptor.schema, normalized, operation) do
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

  defp convert(:window_status, value) when is_integer(value) and value in 0..2,
    do: element(:u8, value)

  defp convert(:nullable_fabric_index, nil), do: element(:null, nil)
  defp convert(:nullable_fabric_index, value), do: scalar_element(:u8, value, 1..254)
  defp convert(:nullable_vendor_id, nil), do: element(:null, nil)
  defp convert(:nullable_vendor_id, value), do: scalar_element(:u16, value, 1..65_534)

  defp convert(:access_control_list, entries) when is_list(entries) and length(entries) <= 64 do
    array(entries, &access_entry/1)
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
  defp scalar_element(type, value, range), do: tagged_scalar(:anonymous, type, value, range)

  defp tagged_scalar(tag, :boolean, value, :boolean) when is_boolean(value),
    do: {:ok, %{tag: tag, type: :boolean, value: value}}

  defp tagged_scalar(tag, type, value, first..last//1)
       when is_integer(value) and value >= first and value <= last,
       do: {:ok, %{tag: tag, type: type, value: value}}

  defp tagged_scalar(_, _, _, _), do: :error
  defp element(type, value), do: {:ok, %{tag: :anonymous, type: type, value: value}}

  defp schema_matches?(:nullable_i16, %{tag: :anonymous, type: :null, value: nil}, _),
    do: true

  defp schema_matches?(:nullable_i16, element, operation),
    do: schema_matches?(:i16, element, operation)

  defp schema_matches?(:i16, %{tag: :anonymous, type: :i16, value: value}, _),
    do: value in -32_768..32_767

  defp schema_matches?(:u8, %{tag: :anonymous, type: :u8, value: value}, _),
    do: value in 0..255

  defp schema_matches?(:boolean, %{tag: :anonymous, type: :boolean, value: value}, _),
    do: is_boolean(value)

  defp schema_matches?(:empty_structure, %{tag: :anonymous, type: :structure, value: []}, _),
    do: true

  defp schema_matches?(:cluster_list, %{tag: :anonymous, type: :array, value: values}, _) do
    Enum.all?(values, fn
      %{tag: :anonymous, type: :u32, value: value} -> valid_cluster?(value)
      _ -> false
    end)
  end

  defp schema_matches?(:parts_list, %{tag: :anonymous, type: :array, value: values}, _),
    do: Enum.all?(values, &match?(%{tag: :anonymous, type: :u16}, &1))

  defp schema_matches?(:device_type_list, %{tag: :anonymous, type: :array, value: values}, _) do
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

  defp schema_matches?(
         :reachable_event,
         %{
           tag: :anonymous,
           type: :structure,
           value: [%{tag: {:context, 0}, type: :boolean, value: value}]
         },
         _
       ),
       do: is_boolean(value)

  defp schema_matches?(:window_status, %{tag: :anonymous, type: :u8, value: value}, _),
    do: value in 0..2

  defp schema_matches?(:nullable_fabric_index, %{tag: :anonymous, type: :null, value: nil}, _),
    do: true

  defp schema_matches?(:nullable_fabric_index, %{tag: :anonymous, type: :u8, value: value}, _),
    do: value in 1..254

  defp schema_matches?(:nullable_vendor_id, %{tag: :anonymous, type: :null, value: nil}, _),
    do: true

  defp schema_matches?(:nullable_vendor_id, %{tag: :anonymous, type: :u16, value: value}, _),
    do: value in 1..65_534

  defp schema_matches?(:access_control_list, %{tag: :anonymous, type: :array, value: values}, op)
       when length(values) <= 64,
       do: Enum.all?(values, &access_entry_element?(&1, op))

  defp schema_matches?(_, _, _), do: false

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

  defp extract(:window_status, %{value: value}), do: {:ok, value}

  defp extract(schema, %{type: :null})
       when schema in [:nullable_fabric_index, :nullable_vendor_id],
       do: {:ok, nil}

  defp extract(schema, %{value: value})
       when schema in [:nullable_fabric_index, :nullable_vendor_id],
       do: {:ok, value}

  defp extract(:access_control_list, %{value: entries}),
    do: {:ok, Enum.map(entries, &extract_access_entry/1)}

  defp extract(_, _), do: :error

  defp access_entry(%{privilege: privilege, auth_mode: auth_mode} = entry) do
    keys = Map.keys(entry)

    with true <-
           keys -- [:privilege, :auth_mode, :subjects, :targets, :auxiliary_type, :fabric_index] ==
             [],
         true <- privilege in 1..5,
         true <- auth_mode in 2..3,
         {:ok, subjects} <- nullable_subjects(Map.get(entry, :subjects)),
         {:ok, targets} <- nullable_targets(Map.get(entry, :targets)),
         {:ok, optional} <- optional_access_fields(entry) do
      {:ok,
       %{
         tag: :anonymous,
         type: :structure,
         value: [
           %{tag: {:context, 1}, type: :u8, value: privilege},
           %{tag: {:context, 2}, type: :u8, value: auth_mode},
           subjects,
           targets
           | optional
         ]
       }}
    else
      _ -> :error
    end
  end

  defp access_entry(_), do: :error

  defp nullable_subjects(nil), do: {:ok, %{tag: {:context, 3}, type: :null, value: nil}}

  defp nullable_subjects(subjects) when is_list(subjects) and length(subjects) <= 64 do
    with true <- Enum.all?(subjects, &is_integer/1),
         true <- Enum.all?(subjects, &(&1 in 0..0xFFFFFFFFFFFFFFFF)) do
      {:ok,
       %{
         tag: {:context, 3},
         type: :array,
         value: Enum.map(subjects, &%{tag: :anonymous, type: :u64, value: &1})
       }}
    else
      _ -> :error
    end
  end

  defp nullable_subjects(_), do: :error
  defp nullable_targets(nil), do: {:ok, %{tag: {:context, 4}, type: :null, value: nil}}

  defp nullable_targets(targets) when is_list(targets) and length(targets) <= 64 do
    with {:ok, values} <- traverse(targets, &access_target/1, []) do
      {:ok, %{tag: {:context, 4}, type: :array, value: values}}
    end
  end

  defp nullable_targets(_), do: :error

  defp access_target(target) when is_map(target) and map_size(target) == 3 do
    with true <- Enum.sort(Map.keys(target)) == [:cluster, :device_type, :endpoint],
         {:ok, cluster} <- nullable_tagged({:context, 0}, :u32, target.cluster, :cluster),
         {:ok, endpoint} <- nullable_tagged({:context, 1}, :u16, target.endpoint, 0..0xFFFE),
         {:ok, device_type} <-
           nullable_tagged({:context, 2}, :u32, target.device_type, 0..0xFFFFFFFF),
         true <- valid_target_selectors?(target.cluster, target.endpoint, target.device_type) do
      {:ok, %{tag: :anonymous, type: :structure, value: [cluster, endpoint, device_type]}}
    else
      _ -> :error
    end
  end

  defp access_target(_), do: :error

  defp valid_target_selectors?(cluster, endpoint, device_type),
    do:
      not (is_nil(cluster) and is_nil(endpoint) and is_nil(device_type)) and
        (is_nil(endpoint) or is_nil(device_type))

  defp nullable_tagged(tag, _, nil, _), do: {:ok, %{tag: tag, type: :null, value: nil}}

  defp nullable_tagged(tag, :u32, value, :cluster) do
    if valid_cluster?(value), do: tagged_scalar(tag, :u32, value, 0..0xFFFFFFFF), else: :error
  end

  defp nullable_tagged(tag, type, value, range), do: tagged_scalar(tag, type, value, range)

  defp optional_access_fields(entry) do
    with {:ok, auxiliary} <- optional_access_field(entry, :auxiliary_type, 5, 0..1),
         {:ok, fabric} <- optional_access_field(entry, :fabric_index, 254, 1..254) do
      {:ok, auxiliary ++ fabric}
    end
  end

  defp optional_access_field(entry, key, tag, range) do
    case Map.fetch(entry, key) do
      :error ->
        {:ok, []}

      {:ok, value} ->
        case tagged_scalar({:context, tag}, :u8, value, range) do
          {:ok, element} -> {:ok, [element]}
          :error -> :error
        end
    end
  end

  defp access_entry_element?(%{tag: :anonymous, type: :structure, value: fields}, operation) do
    by_tag = Map.new(fields, &{&1.tag, &1})
    tags = Map.keys(by_tag)
    required = for id <- 1..4, do: {:context, id}
    allowed = required ++ [{:context, 5}] ++ if(operation == :read, do: [{:context, 254}], else: [])

    length(fields) == map_size(by_tag) and Enum.all?(required, &Map.has_key?(by_tag, &1)) and
      tags -- allowed == [] and privilege?(by_tag[{:context, 1}]) and
      auth_mode?(by_tag[{:context, 2}]) and subjects?(by_tag[{:context, 3}]) and
      targets?(by_tag[{:context, 4}]) and optional_u8?(by_tag[{:context, 5}], 0..1) and
      optional_u8?(by_tag[{:context, 254}], 1..254)
  end

  defp access_entry_element?(_, _), do: false
  defp privilege?(%{type: :u8, value: value}), do: value in 1..5
  defp privilege?(_), do: false
  defp auth_mode?(%{type: :u8, value: value}), do: value in 2..3
  defp auth_mode?(_), do: false
  defp subjects?(%{type: :null, value: nil}), do: true

  defp subjects?(%{type: :array, value: subjects}) when length(subjects) <= 64,
    do: Enum.all?(subjects, &match?(%{tag: :anonymous, type: :u64}, &1))

  defp subjects?(_), do: false
  defp targets?(%{type: :null, value: nil}), do: true

  defp targets?(%{type: :array, value: targets}) when length(targets) <= 64,
    do: Enum.all?(targets, &target_element?/1)

  defp targets?(_), do: false

  defp target_element?(%{tag: :anonymous, type: :structure, value: [cluster, endpoint, device]}) do
    nullable_scalar?(cluster, {:context, 0}, :u32, :cluster) and
      nullable_scalar?(endpoint, {:context, 1}, :u16, 0..0xFFFE) and
      nullable_scalar?(device, {:context, 2}, :u32, 0..0xFFFFFFFF) and
      valid_target_selectors?(
        nullable_value(cluster),
        nullable_value(endpoint),
        nullable_value(device)
      )
  end

  defp target_element?(_), do: false
  defp nullable_scalar?(%{tag: tag, type: :null, value: nil}, tag, _, _), do: true

  defp nullable_scalar?(%{tag: tag, type: type, value: value}, tag, type, :cluster),
    do: valid_cluster?(value)

  defp nullable_scalar?(%{tag: tag, type: type, value: value}, tag, type, range),
    do: is_integer(value) and value in range

  defp nullable_scalar?(_, _, _, _), do: false
  defp optional_u8?(nil, _), do: true
  defp optional_u8?(%{type: :u8, value: value}, range), do: value in range
  defp optional_u8?(_, _), do: false

  defp extract_access_entry(%{value: fields}) do
    values = Map.new(fields, &{&1.tag, &1})

    %{
      privilege: values[{:context, 1}].value,
      auth_mode: values[{:context, 2}].value,
      subjects: extract_nullable_list(values[{:context, 3}], & &1.value),
      targets: extract_nullable_list(values[{:context, 4}], &extract_access_target/1)
    }
    |> maybe_put(:auxiliary_type, values[{:context, 5}])
    |> maybe_put(:fabric_index, values[{:context, 254}])
  end

  defp extract_nullable_list(%{type: :null}, _), do: nil
  defp extract_nullable_list(%{value: values}, function), do: Enum.map(values, function)

  defp extract_access_target(%{value: [cluster, endpoint, device]}) do
    %{
      cluster: nullable_value(cluster),
      endpoint: nullable_value(endpoint),
      device_type: nullable_value(device)
    }
  end

  defp nullable_value(%{type: :null}), do: nil
  defp nullable_value(%{value: value}), do: value
  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, %{value: value}), do: Map.put(map, key, value)
end
