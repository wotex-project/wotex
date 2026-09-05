defmodule Wotex.ValueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.{
    ActionAffordance,
    DataSchema,
    Error,
    EventAffordance,
    Form,
    PropertyAffordance,
    SecurityScheme
  }

  alias Wotex.JSON

  test "DataSchema preserves extension members" do
    map = %{"type" => "number", "x-example:quality" => "measured"}
    assert {:ok, schema} = DataSchema.new(map)
    assert DataSchema.to_map(schema) == map
  end

  test "DataSchema enforces the pinned TD 1.1 definition" do
    assert {:error, %Error{code: :schema_violation, phase: :schema, path: "/type"}} =
             DataSchema.new(%{"type" => "decimal"})

    assert {:error, %Error{code: :schema_violation, phase: :schema, path: "/minItems"}} =
             DataSchema.new(%{"type" => "array", "minItems" => -1})
  end

  test "Form requires href and preserves binding members" do
    map = %{
      "href" => "mqtt://broker.example.test/thing/property",
      "op" => ["readproperty", "observeproperty"],
      "x-example:binding" => %{"revision" => 1}
    }

    assert {:ok, form} = Form.new(map)
    assert Form.href(form) == map["href"]
    assert Form.operations(form) == ["readproperty", "observeproperty"]
    assert Form.to_map(form) == map

    assert {:error, %Error{code: :invalid_member, path: "/href"}} = Form.new(%{})
  end

  test "Form rejects invalid operation shapes" do
    assert {:error, %Error{path: "/op"}} =
             Form.new(%{"href" => "relative", "op" => ["readproperty", nil]})

    assert {:error, %Error{path: "/op"}} = Form.new(%{"href" => "relative", "op" => []})
    assert {:error, %Error{path: "/op"}} = Form.new(%{"href" => "relative", "op" => 1})
  end

  test "Form operation access normalizes string, list, and absence" do
    assert {:ok, one} = Form.new(%{"href" => "relative", "op" => "readproperty"})
    assert Form.operations(one) == ["readproperty"]

    assert {:ok, none} = Form.new(%{"href" => "relative"})
    assert Form.operations(none) == []
  end

  test "Form validates operation names in an explicit interaction context" do
    assert {:ok, _form} =
             Form.new(%{"href" => "relative", "op" => "readproperty"}, for: :property)

    assert {:error, %Error{code: :schema_violation, path: "/op"}} =
             Form.new(%{"href" => "relative", "op" => "invokeaction"}, for: :property)

    assert {:ok, _form} =
             Form.new(%{"href" => "relative", "op" => "invokeaction"}, for: :action)

    assert {:ok, _form} =
             Form.new(%{"href" => "relative", "op" => "subscribeevent"}, for: :event)

    assert {:ok, _form} =
             Form.new(%{"href" => "relative", "op" => "readallproperties"}, for: :thing)

    assert {:error, %Error{code: :invalid_form_context}} =
             Form.new(%{"href" => "relative"}, for: :unknown)
  end

  test "security scheme requires a scheme name" do
    assert {:ok, scheme} = SecurityScheme.new(%{"scheme" => "nosec", "x-note" => true})
    assert SecurityScheme.scheme(scheme) == "nosec"
    assert SecurityScheme.to_map(scheme)["x-note"]

    assert {:error, %Error{path: "/scheme"}} = SecurityScheme.new(%{"scheme" => ""})
  end

  test "security scheme validates standard and extension variants" do
    assert {:ok, _scheme} =
             SecurityScheme.new(%{"scheme" => "apikey", "in" => "header", "name" => "X-Key"})

    assert {:ok, _scheme} =
             SecurityScheme.new(%{"scheme" => "ace:ACESecurityScheme", "ace:cnonce" => true})

    assert {:error, %Error{code: :schema_violation, phase: :schema}} =
             SecurityScheme.new(%{"scheme" => "unknown"})
  end

  test "affordance categories retain distinct types and complete maps" do
    map = %{"title" => "A", "forms" => [%{"href" => "relative"}]}

    assert {:ok, property} = PropertyAffordance.new(map)
    assert {:ok, action} = ActionAffordance.new(map)
    assert {:ok, event} = EventAffordance.new(map)
    assert %PropertyAffordance{} = property
    assert %ActionAffordance{} = action
    assert %EventAffordance{} = event
    assert PropertyAffordance.to_map(property) == map
    assert ActionAffordance.to_map(action) == map
    assert EventAffordance.to_map(event) == map
  end

  test "affordance constructors enforce their TD 1.1 definitions" do
    assert {:error, %Error{code: :schema_violation, phase: :schema}} =
             PropertyAffordance.new(%{"title" => "missing forms"})

    assert {:error, %Error{code: :schema_violation, path: "/safe"}} =
             ActionAffordance.new(%{
               "forms" => [%{"href" => "relative"}],
               "safe" => "yes"
             })

    assert {:error, %Error{code: :schema_violation}} =
             EventAffordance.new(%{"forms" => []})
  end

  test "all value constructors reject non-object values" do
    for constructor <- [
          &DataSchema.new/1,
          &Form.new/1,
          &PropertyAffordance.new/1,
          &ActionAffordance.new/1,
          &EventAffordance.new/1,
          &SecurityScheme.new/1
        ] do
      assert {:error, %Error{code: :object_required}} = constructor.([])
    end
  end

  test "JSON validation reports invalid values and escaped pointer paths" do
    assert JSON.pointer_segment("a/b~c") == "a~1b~0c"
    assert {:error, %Error{code: :invalid_json_value}} = JSON.validate({:not, :json})

    assert {:error, %Error{code: :invalid_json_value, path: "/items/1"}} =
             JSON.validate(%{"items" => [true, {:not, :json}]})
  end

  test "canonical JSON handles every scalar and nested list" do
    value = %{"z" => [nil, true, false, 1, 1.5, "text"], "a" => %{}}
    assert {:ok, json} = JSON.encode(value)
    assert json == ~s({"a":{},"z":[null,true,false,1,1.5,"text"]})
  end

  test "structured errors retain stable matching fields" do
    error = Error.new(:example, :value, "example", "/value", %{limit: 1})
    assert error.code == :example
    assert error.phase == :value
    assert error.path == "/value"
    assert error.details == %{limit: 1}
    assert Exception.message(error) == "example"
  end
end
