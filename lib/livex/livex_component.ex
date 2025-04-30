defmodule Livex.LivexComponent do
  defmodule Schema do
    @moduledoc """
    Injects the Livex DSL into your LiveView modules,
    and automatically generates a `changeset/2` based on
    declared `:attributes` and `:components`.
    """

    use Spark.Dsl,
      default_extensions: [
        extensions: [Livex.Schema.LivexComponentDsl]
      ]
  end

  defmacro __using__(opts \\ []) do
    conditional =
      if __CALLER__.module != Phoenix.LiveView.Helpers do
        quote do: import(Phoenix.LiveView.Helpers)
      end

    imports =
      quote bind_quoted: [opts: opts] do
        import Phoenix.LiveView
        @behaviour Phoenix.LiveComponent
        @before_compile Phoenix.LiveView.Renderer

        @doc false

        import Kernel, except: [def: 2, defp: 2]
        import Phoenix.Component, except: [assign: 2, assign: 3]
        import Phoenix.Component.Declarative
        require Phoenix.Template

        for {prefix_match, value} <- Phoenix.Component.Declarative.__setup__(__MODULE__, opts) do
          @doc false
          def __global__?(unquote(prefix_match)), do: unquote(value)
        end

        import Livex.LivexComponent

        use Schema

        def __live__, do: %{kind: :component, layout: false}

        def push_delete({socket, [key] = path}) do
          # if path is just [:foo], remove the :foo assign entirely
          {Phoenix.Component.assign(socket, key, nil), path}
        end

        def push_delete({socket, path}) do
          [head | tail] = path

          tail
          |> Enum.map(&Access.key(&1, %{}))
          |> then(fn path ->
            put_in(socket.assigns[head] || %{}, path, nil)
          end)
          |> then(&Phoenix.Component.assign(socket, head, &1))
          |> then(&{&1, path})
        end
      end

    [conditional, imports]
  end
end
