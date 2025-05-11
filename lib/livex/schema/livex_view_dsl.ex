defmodule Livex.Schema.LivexViewDsl do
  @moduledoc false

  alias Spark.Dsl.{Entity, Section}
  alias Livex.Schema.{Attr, Data}

  # —————————————————————————————————————————
  # 2) Entity definitions
  # —————————————————————————————————————————
  @attr_entity %Entity{
    name: :prop,
    args: [:name, :type],
    target: Attr,
    schema: [
      name: [type: :atom, doc: "Field name (atom)"],
      type: [type: :atom, doc: "Ecto field type (e.g. :string, :integer, or custom)"]
    ],
    describe: "Define a primitive field"
  }

  @data_entity %Entity{
    name: :data,
    args: [:name, :type],
    target: Data,
    schema: [
      name: [type: :atom, doc: "Field name (atom)"],
      type: [type: :atom, doc: "Ecto field type (e.g. :string, :integar or custom"],
      url?: [type: :boolean, default: false, doc: "Include in url"],
      one_of: [type: {:list, :atom}, doc: "Must be one of these values"]
    ],
    describe: "Define a primitive field"
  }

  # —————————————————————————————————————————
  # 3) Section definitions
  # —————————————————————————————————————————
  @properties_section %Section{
    name: :attributes,
    schema: [],
    entities: [@attr_entity, @data_entity],
    describe: "Group primitive field definitions",
    top_level?: true
  }

  use Spark.Dsl.Extension,
    sections: [@properties_section],
    transformers: []
end
