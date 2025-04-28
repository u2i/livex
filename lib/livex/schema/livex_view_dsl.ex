defmodule Livex.Schema.LivexViewDsl do
  @moduledoc false

  alias Spark.Dsl.{Entity, Section}

  # —————————————————————————————————————————
  # 1) Data carrier structs
  # —————————————————————————————————————————
  defmodule Attribute do
    @moduledoc false
    defstruct [:name, :type, :default]
  end

  defmodule Component do
    @moduledoc false
    defstruct [:name, :related, :cardinality, :default]
  end

  # —————————————————————————————————————————
  # 2) Entity definitions
  # —————————————————————————————————————————
  @attribute_entity %Entity{
    name: :attribute,
    args: [:name, :type],
    target: Attribute,
    schema: [
      name: [type: :atom, doc: "Field name (atom)"],
      type: [type: :atom, doc: "Ecto field type (e.g. :string, :integer, or custom)"],
      default: [type: :any, default: nil, doc: "Default value"]
    ],
    describe: "Define a primitive field"
  }

  @has_one_entity %Entity{
    name: :has_one,
    args: [:name, :related],
    target: Component,
    schema: [
      name: [type: :atom, doc: "Component field name"],
      related: [type: :atom, doc: "Module of component"],
      cardinality: [type: {:in, [:one, :many]}, default: :one, doc: ":one"],
      default: [type: :any, default: nil, doc: "Default struct"]
    ],
    describe: "Define one embedded component"
  }

  @has_many_entity %Entity{
    name: :has_many,
    args: [:name, :related],
    target: Component,
    schema: [
      name: [type: :atom, doc: "Component field name"],
      related: [type: :atom, doc: "Module of component"],
      cardinality: [type: {:in, [:one, :many]}, default: :many, doc: ":many"],
      default: [type: :any, default: [], doc: "Default list"]
    ],
    describe: "Define many embedded components"
  }

  # —————————————————————————————————————————
  # 3) Section definitions
  # —————————————————————————————————————————
  @attributes_section %Section{
    name: :attributes,
    schema: [],
    entities: [@attribute_entity],
    describe: "Group primitive field definitions"
  }

  @components_section %Section{
    name: :components,
    schema: [],
    entities: [@has_one_entity, @has_many_entity],
    describe: "Group embedded component definitions"
  }

  use Spark.Dsl.Extension,
    sections: [@attributes_section, @components_section],
    transformers: [
      Livex.Schema.ChangesetTransformer,
      Livex.Schema.LivexViewTransformer
    ]
end
