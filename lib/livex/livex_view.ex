defmodule Livex.LivexView do
  @moduledoc """
  A module that enhances Phoenix LiveView with automatic state management and lifecycle improvements.

  ## Features

  * **Declarative State Definition**: Define state properties with type safety and URL persistence options
  * **Automatic URL State Management**: State marked with `url?: true` is automatically persisted to the URL
  * **Simplified Lifecycle**: Consolidate data derivation logic in the `pre_render` callback
  * **Dependency-Aware Assignments**: Use `assign_new/4` to compute values only when dependencies change
  * **Reactive Data Streams**: Use `stream_new/4` to automatically update streams when dependencies change
  * **Component State Management**: Define component modules as state types for parent-controlled components

  ## State Management

  Livex allows you to declaratively define state properties for your LiveView:

  ```elixir
  # State stored in URL, survives refreshes, typed as :integer
  state :page_number, :integer, url?: true
  
  # State stored in URL, survives refreshes, typed as :string
  state :category_filter, :string, url?: true
  
  # Client-side state, survives reconnects but not refreshes, typed as :boolean
  state :show_advanced_search, :boolean
  
  # Component state type - parent can control this component's attributes
  state :edit_form, MyApp.Components.EditForm
  ```

  * `url?: true` - State is stored in the URL query string, making it bookmarkable and persistent across page refreshes
  * `url?: false` (or omitted) - State is stored only in client-side LiveView state, surviving reconnects but not refreshes
  * **Type System** - Livex handles casting state from URL (string) or client-side representation to its defined Elixir type
  * **Component State** - When a component module is used as a type, the parent can control that component's attributes

  ## Lifecycle Management

  Livex simplifies the LiveView lifecycle by consolidating data derivation and initial assignment logic 
  into a `pre_render/1` callback. This largely replaces both `mount/3` and `handle_params/3`, providing 
  a single place to handle state initialization and data derivation.

  The typical flow becomes: render -> event -> reducer (handle_event, handle_info, handle_async) -> pre_render -> render.

  ```elixir
  def pre_render(socket) do
    {:noreply,
     socket
     |> assign_new(:page_title, fn -> "Product Catalog" end)
     |> assign_new(:selected_category, fn -> "all" end)
     |> assign_new(:products, [:selected_category], fn assigns ->
       # This function only runs if selected_category changes
       Products.list_by_category(assigns.selected_category)
     end)}
  end
  ```

  ## Dependency-Aware Assignments

  The `assign_new/4` function extends Phoenix.Component.assign_new/3 with dependency tracking:

  ```elixir
  # Runs only when user_id changes
  assign_new(socket, :profile, [:user_id], fn assigns ->
    Accounts.get_user_profile(assigns.user_id)
  end)
  
  # Initial assignment (no dependencies)
  assign_new(socket, :is_admin_view, fn -> false end)
  ```

  ## Reactive Data Streams

  The `stream_new/4` function enhances LiveView's stream/4 with dependency tracking:

  ```elixir
  # Stream resets and repopulates when filter_category or filter_price_range changes
  stream_new(socket, :products, [:filter_category, :filter_price_range], fn assigns ->
    filter_products(
      Products.list_all(),
      assigns.filter_category,
      assigns.filter_price_range
    )
  end)
  ```

  ## Usage Example

  ```elixir
  defmodule MyApp.ProductListingView do
    use Livex.LivexView
    
    state :selected_category, :string, url?: true
    state :sort_by, :atom, url?: true
    state :modal_open, :boolean
    state :edit_form, MyApp.Components.EditForm
    
    def pre_render(socket) do
      {:noreply,
       socket
       |> assign_new(:modal_open, fn -> false end)
       |> assign_new(:page_title, fn -> "Product Catalog" end)
       |> assign_new(:selected_category, fn -> "all" end)
       |> assign_new(:sort_by, fn -> :name_asc end)
       |> stream_new(:products, [:selected_category, :sort_by], fn assigns ->
         Products.list_available_products(
           category: assigns.selected_category,
           order_by: assigns.sort_by
         )
       end)}
    end
    
    def render(assigns) do
      ~H\"\"\"
      <div>
        <h1>{@page_title}</h1>
        
        <.live_component
          :if={@edit_form}
          module={MyApp.Components.EditForm}
          id="edit-form"
          {@edit_form}
          phx-close="close_form"
        />
        
        <!-- Product listing and filters -->
      </div>
      \"\"\"
    end
    
    def handle_event("close_form", _, socket) do
      {:noreply, assign(socket, :edit_form, nil)}
    end
  end
  ```
  """

  defmodule Schema do
    @moduledoc false
    use Spark.Dsl,
      default_extensions: [
        extensions: [Livex.Schema.LivexViewDsl]
      ]
  end

  defmacro __using__(_opts) do
    quote do
      use Phoenix.LiveView
      use Schema

      defdelegate push_js(socket, event), to: Livex.Utils
      defdelegate assign_new(socket, key, deps, fun), to: Livex.Utils
      defdelegate stream_new(socket, key, deps, fun), to: Livex.Utils

      on_mount {__MODULE__, :__livex}

      def on_mount(:__livex, params, session, socket) do
        Livex.LivexView.on_mount(__MODULE__, params, session, socket)
      end

      @before_compile unquote(__MODULE__)
    end
  end

  # This runs *after* the module has compiled all its own defs.
  defmacro __before_compile__(_env) do
    quote do
      defoverridable render: 1

      def render(assigns) do
        super(assigns) |> Livex.RenderedManipulator.wrap_in_div(__MODULE__, assigns)
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
        def handle_event(_event, _params, socket) do
          pre_render(socket)
        end
      end

      if Module.defines?(__MODULE__, {:handle_params, 3}, :def) do
        defoverridable handle_params: 3

        @impl true
        def handle_params(params, uri, socket) do
          {:noreply, socket} = super(params, uri, socket)
          pre_render(socket)
        end
      else
        @impl true
        def handle_params(_params, _uri, socket) do
          pre_render(socket)
        end
      end

      if Module.defines?(__MODULE__, {:handle_info, 2}, :def) do
        defoverridable handle_info: 2

        @impl true
        def handle_info(msg, socket) do
          {:noreply, socket} = super(msg, socket)
          pre_render(socket)
        end
      else
        @impl true
        def handle_info(_msg, socket) do
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

  alias Livex.ParamsMapper
  alias Phoenix.Component

  def assign_from_uri(module, params, uri, socket) when is_atom(module) and is_map(params) do
    socket
    |> Component.assign(:uri, uri)
    |> Component.assign(ParamsMapper.map_params(module, params))
    # TODO: only reset changed values modified by map_params (probably leave it unchanged)
    |> then(fn socket -> put_in(socket.assigns.__changed__, %{}) end)
    |> then(&{:cont, &1})
  end

  def on_mount(module, params, _session, socket) do
    {:cont, socket} = Livex.LivexView.assign_from_uri(module, params, nil, socket)

    socket =
      socket
      |> Phoenix.LiveView.attach_hook(
        :set_params,
        :handle_params,
        fn params, uri, socket ->
          Process.put(:__current_params, params)

          %URI{path: current_path, host: host} = URI.parse(uri)

          %{route: pattern} =
            Phoenix.Router.route_info(socket.router, "GET", current_path, host)

          Process.put(:__current_route, pattern)
          {:cont, socket}
        end
      )
      |> Phoenix.LiveView.attach_hook(
        :save_uri,
        :handle_params,
        fn params, uri, socket ->
          Livex.LivexView.assign_from_uri(module, params, uri, socket)
        end
      )
      |> Phoenix.LiveView.attach_hook(
        :component_action,
        :handle_event,
        fn
          "__component_action", params, socket ->
            {:noreply, socket} =
              Livex.Handlers.handle_component_event(
                module,
                params,
                socket
              )

            {:halt, socket}

          _, _, socket ->
            {:cont, socket}
        end
      )
      |> Phoenix.LiveView.attach_hook(
        :clear_params,
        :after_render,
        fn socket ->
          Process.put(:__current_params, nil)
          socket
        end
      )

    {:cont, socket}
  end
end
