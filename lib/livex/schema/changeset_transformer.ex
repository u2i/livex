defmodule Livex.Schema.ChangesetTransformer do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Extension
  alias Livex.Schema.Changeset

  @impl Spark.Dsl.Transformer
  def transform(dsl_state) do
    alias Livex.Schema.ChangesetTransformer

    validate =
      quote do
        def changeset(input, state) do
          ChangesetTransformer.changeset(__MODULE__, input, state)
        end

        def __changeset__ do
          ChangesetTransformer.__changeset__(__MODULE__)
        end
      end

    {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], validate)}
  end

  def changeset(module, assigns, params) do
    attrs =
      Extension.get_entities(module, [:attributes])
      |> Enum.map(& &1.name)

    components =
      Extension.get_entities(module, [:components])
      |> Enum.map(& &1.name)

    assigns
    |> Map.put(:module, module)
    |> Changeset.cast(module, params, attrs)
    |> cast_embeds(components)
  end

  defp cast_embeds(changeset, embeds) do
    Enum.reduce(embeds, changeset, fn embed, acc ->
      Changeset.cast_embed(acc, embed)
    end)
  end

  def __changeset__(module) do
    attributes =
      Extension.get_entities(module, [:attributes])
      |> Enum.map(&{&1.name, &1.type})

    components =
      Extension.get_entities(module, [:components])
      |> Enum.map(fn component ->
        {component.name, {:embed, component.related.__changeset__()}}
      end)

    (attributes ++ components)
    |> Map.new()
  end
end
