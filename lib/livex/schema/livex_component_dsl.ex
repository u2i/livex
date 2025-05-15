defmodule Livex.Schema.LivexComponentDsl do
  @moduledoc false

  alias Spark.Dsl.{Entity, Section}
  alias Livex.Schema.{Attr, State, Event, Value}

  # —————————————————————————————————————————
  # 2) Entity definitions
  # —————————————————————————————————————————
  @attr_entity %Entity{
    name: :attr,
    args: [:name, :type],
    target: Attr,
    schema: [
      name: [type: :atom, doc: "Field name (atom)"],
      type: [type: :atom, doc: "Ecto field type (e.g. :string, :integer, or custom)"]
    ],
    describe: "Define a primitive field"
  }

  @state_entity %Entity{
    name: :state,
    args: [:name, :type],
    target: State,
    schema: [
      name: [type: :atom, doc: "Field name (atom)"],
      type: [type: :atom, doc: "Ecto field type (e.g. :string, :integar or custom"],
      url?: [type: :boolean, default: false, doc: "Include in url"],
      one_of: [type: {:list, :atom}, doc: "Must be one of these values"]
    ],
    describe: "Define a primitive field"
  }

  @value_entity %Entity{
    name: :value,
    args: [:name, :type],
    target: Value,
    schema: [
      name: [type: :atom, doc: "Field name (atom)"],
      type: [type: :atom, doc: "Ecto field type (e.g. :string, :integer, or custom)"]
    ],
    describe: "Define a primitive field"
  }

  @event_entity %Entity{
    name: :event,
    args: [:name],
    target: Event,
    schema: [
      name: [type: :atom, doc: "Event name (atom)"]
    ],
    entities: [
      values: [@value_entity]
    ],
    describe: "Define a primitive field"
  }

  # —————————————————————————————————————————
  # 3) Section definitions
  # —————————————————————————————————————————
  @properties_section %Section{
    name: :attributes,
    schema: [],
    entities: [@attr_entity, @state_entity, @event_entity],
    describe: "Group primitive field definitions",
    top_level?: true
  }

  use Spark.Dsl.Extension,
    sections: [@properties_section],
    transformers: []
end
