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

        def create_component(socket_path, id, assigns) do
          ChangesetTransformer.create_component(__MODULE__, socket_path, id, assigns)
        end

        def assign_({socket, path}, map) when is_map(map) do
          Enum.reduce(map, {socket, path}, fn {k, v}, acc ->
            assign_(acc, k, v)
          end)
        end

        def assign_({socket, path}, id, value) do
          [head | tail] = path ++ [id]

          tail
          |> Enum.map(&Access.key(&1, %{}))
          |> then(fn path ->
            put_in(socket.assigns[head] || %{}, path, value)
          end)
          |> then(&assign(socket, head, &1))
          |> then(&{&1, path})
        end

        def assign_new_({socket, path} = socket_path, id, f) do
          unless assigns(socket_path)[id] do
            assign_(socket_path, id, f.())
          else
            socket_path
          end
        end

        def assigns({socket, path}) do
          path
          |> Enum.map(&Access.key(&1, %{}))
          |> then(fn path -> get_in(socket.assigns, path) end)
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

  def create_component(module, %Phoenix.LiveView.Socket{} = socket, id, assigns) do
    {socket, _} = create_component(module, {socket, []}, id, assigns)
    socket
  end

  def create_component(module, {socket, og_path}, id, assigns) do
    component = Extension.get_entities(module, [:components]) |> Enum.find(&(&1.name == id))

    {socket, _path} =
      module.assign_({socket, og_path ++ [component.name]}, %{
        id: component.name,
        path: og_path ++ [component.name]
      })

    {:ok, {socket, _path}} =
      component.related.mount(assigns, {socket, og_path ++ [component.name]})

    {socket, og_path}
  end
end
