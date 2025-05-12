defmodule Livex.LivexComponent do
  @moduledoc """
  A module that enhances Phoenix LiveComponent with automatic state management and lifecycle improvements.

  ## Features

  * **Declarative State Definition**: Define component state properties with type safety
  * **Component Properties (attr)**: Define expected properties passed from parent
  * **Simplified Lifecycle**: Consolidate data derivation logic in the `pre_render` callback
  * **Dependency-Aware Assignments**: Use `assign_new/4` to compute values only when dependencies change
  * **Simplified State Updates**: Use `JSX.assign_data` for direct state updates from templates
  * **Component Events**: Emit events to parent views with `push_emit` or `JSX.emit`
  * **PubSub Integration**: Subscribe to topics with dependency-aware `assign_topic`

  ## State and Properties

  Livex components use two key concepts for managing data:

  1. **state** - Internal component state that persists across renders
  2. **attr** - Properties passed down from parent components/views

  ### Component State

  ```elixir
  # Client-side state, survives reconnects but not refreshes
  state :is_expanded, :boolean
  state :selected_tab, :string
  state :current_count, :integer
  ```

  ### Component Properties (attr)

  ```elixir
  # Properties passed from parent
  attr :id, :string, required: true
  attr :item_id, :string
  attr :initial_value, :string
  attr :on_save, :any
  ```

  ## Lifecycle Management

  Livex simplifies the component lifecycle by consolidating data derivation and initial 
  assignment logic into a `pre_render/1` callback. This is where you can initialize state 
  based on attr values or compute derived data.

  ```elixir
  def pre_render(socket) do
    {:noreply,
     socket
     |> assign_new(:is_expanded, fn -> false end)
     |> assign_new(:pending_selection, [:selected_value], &(&1.selected_value))
     |> assign_new(:has_changes, fn -> false end)
     |> then(fn socket ->
       # Compute derived state
       assign(socket, :has_changes, 
         socket.assigns.pending_selection != socket.assigns.selected_value)
     end)}
  end
  ```

  ## Simplified State Updates

  Livex introduces `JSX.assign_data` for updating component state directly from templates:

  ```elixir
  # Update a single value
  <button phx-click={JSX.assign_data(:is_expanded, true)}>Expand</button>
  
  # Update multiple values
  <button phx-click={JSX.assign_data(is_expanded: false, selected_tab: "details")}>
    Close
  </button>
  
  # Conditional updates
  <button phx-click={
    if @is_expanded do
      JSX.assign_data(is_expanded: false, pending_value: @initial_value)
    else
      JSX.assign_data(is_expanded: true)
    end
  }>
    {if @is_expanded, do: "Close", else: "Expand"}
  </button>
  ```

  ## Component Events

  Livex enhances event handling for components, allowing them to emit custom events 
  that parent LiveViews or LiveComponents can listen for:

  ### Emitting from templates:

  ```elixir
  <button phx-click={JSX.emit(:save, value: %{id: @id, data: @form_data})}>
    Save Changes
  </button>
  ```

  ### Emitting from Elixir code:

  ```elixir
  def handle_event("save_changes", _, socket) do
    # Process the data...
    
    # Emit an event to the parent
    socket = push_emit(socket, :saved, %{id: socket.assigns.id})
    {:noreply, assign(socket, :is_saving, false)}
  end
  ```

  ### Handling in parent:

  ```elixir
  <.live_component
    module={MyApp.FormComponent}
    id="my-form"
    phx-saved="handle_form_saved"
  />
  
  # In the parent's handle_event
  def handle_event("handle_form_saved", %{"id" => id}, socket) do
    # Handle the saved event
    {:noreply, socket}
  end
  ```

  ## PubSub Integration

  Livex makes it easier for components to subscribe to PubSub topics with `assign_topic`:

  ```elixir
  def pre_render(socket) do
    {:noreply,
     socket
     |> assign_new(:status_message, fn -> "Connecting..." end)
     |> assign_topic(:doc_updates, [:document_id], fn assigns ->
       "document_updates:\#{assigns.document_id}"
     end)}
  end
  
  # Handle PubSub messages
  def handle_info({:doc_updates, %{message: msg}}, socket) do
    {:noreply, assign(socket, :status_message, msg)}
  end
  ```

  ## Complete Example

  ```elixir
  defmodule MyApp.FormComponent do
    use Livex.LivexComponent
    
    attr :id, :string, required: true
    attr :item_id, :string
    attr :on_save, :any
    
    state :is_expanded, :boolean
    state :form_data, :map
    state :is_valid, :boolean
    
    def pre_render(socket) do
      {:noreply,
       socket
       |> assign_new(:is_expanded, fn -> false end)
       |> assign_new(:form_data, [:item_id], fn assigns ->
         if assigns.item_id, do: load_item(assigns.item_id), else: %{}
       end)
       |> assign_new(:is_valid, [:form_data], fn assigns ->
         validate_form(assigns.form_data)
       end)}
    end
    
    def render(assigns) do
      ~H\"\"\"
      <div id={@id} class="form-component">
        <h3>Edit Item</h3>
        
        <div class="form-fields">
          <!-- Form fields here -->
        </div>
        
        <div class="actions">
          <button 
            disabled={!@is_valid}
            phx-click="save"
            phx-target={@myself}>
            Save
          </button>
          
          <button phx-click={JSX.emit(:cancel)}>
            Cancel
          </button>
        </div>
      </div>
      \"\"\"
    end
    
    def handle_event("save", _, socket) do
      # Process the save...
      if socket.assigns.on_save do
        socket.assigns.on_save.(socket.assigns.form_data)
      end
      
      # Emit an event to the parent
      socket = push_emit(socket, :saved, %{id: socket.assigns.id})
      {:noreply, socket}
    end
    
    defp load_item(id) do
      # Load item data
    end
    
    defp validate_form(data) do
      # Validate form data
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

      import Phoenix.LiveView
      @behaviour Phoenix.LiveComponent
      @before_compile Phoenix.LiveView.Renderer

      import Phoenix.Component, except: [attr: 2, attr: 3]

      # import Phoenix.Component.Declarative
      require Phoenix.Template

      @doc false
      def __live__, do: %{kind: :component, layout: false}

      # use Phoenix.LiveComponent, except: [def: 2, defp: 2, attr: 2, attr: 3]

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
      defdelegate stream_new(socket, key, deps, fun), to: Livex.Utils

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
    socket =
      if current_params do
        # we only have params when we're rehydrating, so we need to reset the changed status
        socket
        |> map_params(module, current_params, assigns)
        |> assign_all_from_parent_or_call_original(assigns, super)
        |> then(fn {:ok, socket} -> put_in(socket.assigns.__changed__, %{}) end)
      else
        # otherwise we should proceed 
        {:ok, socket} = assign_all_from_parent_or_call_original(socket, assigns, super)
        socket
      end

    {:noreply, socket} = module.pre_render(socket)
    {:ok, socket}
  end

  defp map_params(socket, module, current_params, assigns) do
    ParamsMapper.map_params(module, current_params, "_#{assigns.id}")
    |> then(&Component.assign(socket, &1))
  end

  defp assign_all_from_parent_or_call_original(socket, assigns, super) when not is_nil(super),
    do: super.(assigns, socket)

  defp assign_all_from_parent_or_call_original(socket, assigns, _) do
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
