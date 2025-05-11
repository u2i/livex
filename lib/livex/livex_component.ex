defmodule Livex.LivexComponent do
  @moduledoc """
  A module that enhances Phoenix LiveComponent with automatic state management and lifecycle improvements.

  ## Features

  * Automatic state management with optional URL persistence
  * Simplified component lifecycle with `pre_render` function
  * Improved event handling with automatic state updates
  * Custom event emission with `push_emit`
  * Declarative state dependencies with `assign_new/4`

  ## Usage

  ```elixir
  defmodule MyApp.FormComponent do
    use Livex.LivexComponent
    
    state :is_expanded, :boolean
    state :selected_tab, :string, url?: true
    
    def pre_render(socket) do
      {:noreply, socket}
    end
    
    def render(assigns) do
      ~H\"\"\"
      <div>
        <!-- Your component template here -->
        <button phx-click={JSX.emit(:close)}>Cancel</button>
      </div>
      \"\"\"
    end
    
    # Handle the close event
    def handle_event("close", _, socket) do
      {:noreply, socket |> push_emit(:close)}
    end
  end
  ```
  """

  defmodule Schema do
    @moduledoc false
    use Spark.Dsl,
      default_extensions: [extensions: [Livex.Schema.LivexComponentDsl]]
  end

  defmacro __using__(_opts \\ []) do
    quote do
      use Schema
      import Phoenix.LiveView.Helpers

      @impl true
      def handle_event("__component_action", params, socket) do
        Livex.Handlers.handle_component_event(
          __MODULE__,
          params,
          socket
        )
      end

      alias Phoenix.LiveView.Socket

      defdelegate push_emit(socket, event, opts), to: Livex.Utils
      defdelegate push_js(socket, event), to: Livex.Utils
      defdelegate assign_new(socket, key, deps, fun), to: Livex.Utils

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      @update_defined? Module.defines?(__MODULE__, {:update, 2}, :def)

      if @update_defined? do
        defoverridable update: 2

        @impl true
        def update(assigns, socket) do
          Livex.LivexComponent.override_update(
            assigns,
            socket,
            Process.get(:__current_params),
            __MODULE__,
            &super(&1, &2)
          )
        end
      else
        @impl true
        def update(assigns, socket) do
          Livex.LivexComponent.override_update(
            assigns,
            socket,
            Process.get(:__current_params),
            __MODULE__,
            nil
          )
        end
      end

      defoverridable render: 1

      def render(assigns) do
        super(assigns) |> Livex.LivexComponent.inject_after_div(__MODULE__, assigns)
      end

      if Module.defines?(__MODULE__, {:handle_event, 3}, :def) do
        defoverridable handle_event: 3

        @impl true
        def handle_event(event, params, socket) do
          super(event, params, socket)
          |> handle_event_result()
        end

        def handle_event_result({:noreply, socket}) do
          pre_render(socket)
        end

        def handle_event_result({:reply, msg, socket}) do
          {:noreply, socket} = pre_render(socket)
          {:reply, msg, socket}
        end
      else
        def handle_event(event, params, socket) do
          pre_render(socket)
        end
      end

      if Module.defines?(__MODULE__, {:handle_async, 3}, :def) do
        defoverridable handle_async: 3

        @impl true
        def handle_async(name, result, socket) do
          {:noreply, socket} = super(name, result, socket)
          pre_render(socket)
        end
      else
        @impl true
        def handle_async(_name, _result, socket) do
          pre_render(socket)
        end
      end
    end
  end

  alias Spark.Dsl.Extension
  alias Livex.{ParamsMapper, RenderedManipulator}
  alias Phoenix.Component

  def override_update(%{__dispatch_event: fun, data: data} = _assigns, socket, _, _) do
    fun.(data, socket)
    socket
  end

  def override_update(assigns, socket, current_params, module, super) do
    {:ok, socket} =
      socket
      |> maybe_map_params(module, current_params, assigns)
      |> assign_all_or_call_original(assigns, super)

    {:noreply, socket} = module.pre_render(socket)
    {:ok, socket}
  end

  defp maybe_map_params(socket, _, nil, _), do: socket

  defp maybe_map_params(socket, module, current_params, assigns) do
    ParamsMapper.map_params(module, current_params, "_#{assigns.id}")
    |> then(&Component.assign(socket, &1))
  end

  defp assign_all_or_call_original(socket, assigns, super) when not is_nil(super),
    do: super.(assigns, socket)

  defp assign_all_or_call_original(socket, assigns, _) do
    {:ok,
     assigns
     |> Enum.filter(
       &(!Map.has_key?(socket.assigns, &1 |> elem(0)) ||
           socket.assigns[&1 |> elem(0)] != &1 |> elem(1))
     )
     |> Map.new()
     |> then(&Phoenix.Component.assign(socket, &1))}
  end

  def inject_after_div(%Phoenix.LiveView.Rendered{} = rendered, module, assigns) do
    attributes = Extension.get_entities(module, [:attributes])
    RenderedManipulator.manipulate_rendered(:inject, rendered, attributes, assigns)
  end
end
