# Livex

**This is not production code. It's a (fully functional) DX experiment to be able
to experiment with the combination of various features. But uses elixir trickery
and rather too much knowledge of liveview internals to make it work. Ideally the
end state is either for the features to be added to liveview, or for the
capability to add the features to be added.**

Livex is a library that provides type-safe LiveView components and views with 
enhanced state management, including URL persistence and more declarative data 
handling. It's an opinionated approach to solving common LiveView development 
challenges, drawing inspiration from patterns in frameworks like React.

## Why Livex?

LiveView is a powerful platform for building interactive web applications. 
However, as applications grow, certain patterns can become cumbersome:

- **URL State Management:** While storing state in the URL is crucial for 
  resilience (surviving refreshes, back button), manipulating individual query 
  parameters can be less ergonomic than direct state updates.
- **LiveComponent State:** Managing state within `LiveComponent`s robustly often 
  involves delegating to the parent and manually merging state concerns into the 
  URL query string, which can become complex.
- **Clear State Patterns:** Defining clear patterns for different types of state 
  (parent-owned, child-owned, persistent, ephemeral) and how they transition can 
  be challenging.
- **Derived State Updates:** Reacting to changes in URL parameters or component 
  arguments to refresh externally stored or derived state is often handled 
  imperatively, whereas a more declarative, event-driven approach could be 
  beneficial.
- **Component PubSub:** Enabling components to be self-sufficient in terms of 
  real-time messaging via PubSub can require boilerplate.

Livex aims to address these points by introducing features that promote a more 
declarative and streamlined developer experience, fitting within the existing 
LiveView paradigm while borrowing well-established concepts.

## Installation

The package can be installed by adding `livex` to your list of dependencies in
`mix.exs`:

```elixir
def deps do
  [
    {:livex, "~> 0.1.0"}
  ]
end
```

## Demo

To see Livex in action with concrete examples, check out the demo application at 
https://github.com/u2i/livex_demo. The examples below are synthetic to 
illustrate the core concepts.

## Features

### Declarative State Definition (state)

Livex allows you to declaratively define state properties for your LivexView or 
LivexComponent.

```elixir
defmodule MyAppWeb.ArticleView do
  use MyAppWeb, :livex_view # Or use Livex.LivexView directly

  # State stored in URL, survives refreshes, typed as :integer
  state :page_number, :integer, url?: true
  # State stored in URL, survives refreshes, typed as :string
  state :category_filter, :string, url?: true
  # Client-side state, survives reconnects but not refreshes, typed as :boolean
  state :show_advanced_search, :boolean

  # Example of a component state type.
  # The `MyAppWeb.Components.CommentForm` component's attrs will be managed here.
  # This allows the parent view to control the initial state or reset the form.
  state :new_comment_form, MyAppWeb.Components.CommentForm
  state :edit_comment_form, MyAppWeb.Components.CommentForm # Initially nil

  # rest of your view code...
end

defmodule MyAppWeb.Components.InteractiveCard do
  use MyAppWeb, :livex_component # Or use Livex.LivexComponent directly

  # State specific to this card instance, can be stored in URL if needed
  state :display_mode, :atom # :summary or :detailed
  state :user_rating, :integer, url?: false # Client-side only for this component instance

  # rest of your component code...
end
```
- `state <param_name>, <type>`: Defines a piece of state.
- `url?: true`: Indicates the state should be stored in the URL query string. 
  This makes the state bookmarkable and persistent across page refreshes.
- `url?: false` (or omitted): Indicates the state is stored only on the 
  client-side LiveView state. It will survive client-server reconnects but not 
  full page refreshes.
- **Type System**: Livex handles casting the state from the URL (string) or 
  client-side representation back to its defined Elixir type.
- **Component State**: You can define a state property as a component module 
  (e.g., `state :new_comment_form, MyAppWeb.Components.CommentForm`). Livex will 
  then manage the attributes (attr) of this component as part of the parent's 
  state. When this state is updated (e.g., via JSX.assign_data or a direct 
  assign in an event), Livex facilitates the re-rendering of the child component 
  with the new attribute values.
- **Initial Values**: Default values are not directly supported in the state 
  macro. To set an initial value, use assign_new/2 within the pre_render/1 
  callback without dependencies, e.g., `assign_new(socket, :my_state, fn -> 
  initial_value end)`.

### Simplified State Updates (JSX.assign_data)

For components, Livex introduces JSX.assign_data (used within HEEx templates) as 
a convenient way to update its own state properties. This is analogous to the 
setter functions returned by useState in React functional components. It 
simplifies common cases of updating component state directly from template 
events without needing a full handle_event callback for simple assignments.

Example:

```elixir
defmodule MyAppWeb.Components.CounterButton do
  use MyAppWeb, :livex_component

  state :current_count, :integer
  state :is_highlighted, :boolean

  def pre_render(socket) do
    # Set initial values using assign_new without dependencies
    {:noreply,
      socket
      |> assign_new(:current_count, fn -> 0 end)
      |> assign_new(:is_highlighted, fn -> false end)
    }
  end

  def render(assigns) do
    ~H"""
    <div>
      <p class={if @is_highlighted, do: "font-bold", else: ""}>
        Count: {@current_count}
      </p>
      <button phx-click={JSX.assign_data(:current_count, @current_count + 1)}>
        Increment
      </button>
      <button phx-click={JSX.assign_data(is_highlighted: !@is_highlighted)}>
        Toggle Highlight
      </button>
      <button phx-click={JSX.assign_data(current_count: 0, is_highlighted: false)}>
        Reset
      </button>
    </div>
    """
  end
end
```
Clicking these buttons will directly update the :current_count and/or 
:is_highlighted state of the CounterButton component instance, triggering a 
re-render. JSX.assign_data can update one or multiple state fields. For more 
complex state transitions or side effects, you would still use handle_event.

### Declarative Data Derivation and Lifecycle Management (pre_render, assign_new, stream_new)

Livex aims to simplify the LiveView/LiveComponent lifecycle (mount, update, 
handle_params) by consolidating data derivation and initial assignment logic 
into a pre_render/1 callback, coupled with enhanced assign and stream functions.

The typical flow becomes: render -> event -> reducer (handle_event, handle_info, 
handle_async) -> pre_render -> render.

- **attr**: Used in LivexComponent to define properties passed down from a 
  parent. These are analogous to "props" in React and are fully controlled by 
  the parent.

```elixir
# In MyAppWeb.Components.ProductDetails
attr :product_sku, :string, required: true
attr :show_pricing, :boolean
```
- **pre_render/1**: A callback where you can declaratively derive state or 
  assign values based on current state or attr values before render/1 is called. 
  This is the primary place to manage data fetching or computation based on 
  dependencies.
- **assign_new/3 or assign_new/2**: Works like Phoenix.Component.assign_new/3, 
  but with an explicit list of dependencies (assign keys). The assignment 
  function will only re-run if one of these dependencies has changed. This 
  memoization helps avoid redundant computations or data fetching. Can also be 
  used without dependencies to set initial values.

Example:

```elixir
defmodule MyAppWeb.UserProfileView do
  use MyAppWeb, :livex_view

  state :user_id, :string, url?: true # e.g., from URL like /users/:user_id

  def pre_render(socket) do
    {:noreply,
     socket
     |> assign_new(:profile, [:user_id], fn assigns ->
       # This function only runs if assigns.user_id changes
       Accounts.get_user_profile(assigns.user_id)
     end)
     |> assign_new(:activity_feed, [:user_id], fn assigns ->
       Activity.fetch_feed_for_user(assigns.user_id)
     end)
     |> assign_new(:is_admin_view, fn -> false end) # Initial assignment
    }
  end
  # ... render, handle_event, etc.
end
```
If :user_id (which is a state field) changes, the functions to fetch :profile 
and :activity_feed will be re-executed.

- **stream_new/4**: An enhancement to LiveView's stream/4. It takes an 
  additional list of dependencies (assign keys from state or attr). The stream 
  will be reset and re-populated using the provided function if any of these 
  dependencies change. This is particularly useful for streams whose contents 
  depend on filter parameters or other dynamic data.

Example:

```elixir
defmodule MyAppWeb.ProductListingView do
  use MyAppWeb, :livex_view

  state :selected_category, :string, url?: true
  state :sort_by, :atom, url?: true

  def pre_render(socket) do
    {:noreply,
     socket
     # Set initial values for filters if not present in URL
     |> assign_new(:selected_category, fn -> "all" end)
     |> assign_new(:sort_by, fn -> :name_asc end)
     # Stream depends on the potentially initialized state values
     |> stream_new(:products, [:selected_category, :sort_by], fn assigns ->
       # This function re-runs if selected_category or sort_by changes
       Products.list_available_products(
         category: assigns.selected_category,
         order_by: assigns.sort_by
       )
     end)}
  end
  # ... render, handle_event to change filters, etc.
end
```
If either :selected_category or :sort_by changes, the :products stream will be 
automatically updated by re-invoking the stream configuration function with the 
new assigns.

### Component Events (push_emit, phx-event)

Livex enhances event handling for components, allowing them to emit custom 
events that parent LiveViews or LiveComponents can listen for, similar to how 
standard phx-click and other events work.

- **Emitting from the component's template**: Use JSX.emit(:event_name, value: 
  %{...}) within a phx-click or other event binding.
- **Emitting from the component's Elixir code**: Use push_emit(socket, 
  :event_name, payload \\ %{}).

Example:

Child Component (MyAppWeb.Components.EditableField):

```elixir
defmodule MyAppWeb.Components.EditableField do
  use MyAppWeb, :livex_component

  attr :field_id, :string, required: true
  attr :initial_value, :string
  state :current_value, :string
  state :is_editing, :boolean

  def pre_render(socket) do
    # Initialize current_value from attr and set editing to false initially
    {:noreply,
      socket
      |> assign_new(:current_value, [:initial_value], &(&1.initial_value))
      |> assign_new(:is_editing, fn -> false end)
    }
  end

  def render(assigns) do
    ~H"""
    <div>
      <%= if @is_editing do %>
        <input type="text" phx-target={@myself} phx-change="update_value" value={@current_value} />
        <button phx-target={@myself} phx-click="save_changes">Save</button>
        <button phx-target={@myself} phx-click={JSX.assign_data(is_editing: false)}>Cancel</button>
      <% else %>
        <span><%= @current_value %></span>
        <button phx-target={@myself} phx-click={JSX.assign_data(is_editing: true)}>Edit</button>
      <% end %>
    </div>
    """
  end

  def handle_event("update_value", %{"value" => new_val}, socket) do
    {:noreply, assign(socket, :current_value, new_val)}
  end

  def handle_event("save_changes", _, socket) do
    # Emit an event to the parent with the field_id and new value
    socket = push_emit(socket, :field_updated, %{id: socket.assigns.field_id, value: socket.assigns.current_value})
    {:noreply, assign(socket, :is_editing, false)}
  end
end
```
Parent View (MyAppWeb.SettingsView):

```elixir
defmodule MyAppWeb.SettingsView do
  use MyAppWeb, :livex_view

  state :username, :string
  state :email, :string

  def pre_render(socket) do
    # Set initial values for settings
    {:noreply,
      socket
      |> assign_new(:username, fn -> "User123" end)
      |> assign_new(:email, fn -> "user@example.com" end)
    }
  end

  def render(assigns) do
    ~H"""
    <div>
      <h2>Settings</h2>
      <label>Username:</label>
      <.live_component
        module={MyAppWeb.Components.EditableField}
        id={"username_field"}
        field_id="username"
        initial_value={@username}
        phx-field_updated="handle_setting_change"
      />
      <label>Email:</label>
      <.live_component
        module={MyAppWeb.Components.EditableField}
        id={"email_field"}
        field_id="email"
        initial_value={@email}
        phx-field_updated="handle_setting_change"
      />
    </div>
    """
  end

  def handle_event("handle_setting_change", %{"id" => "username", "value" => new_username}, socket) do
    # Persist username change, update local state
    {:noreply, assign(socket, :username, new_username)}
  end

  def handle_event("handle_setting_change", %{"id" => "email", "value" => new_email}, socket) do
    # Persist email change, update local state
    {:noreply, assign(socket, :email, new_email)}
  end
end
```
### Enable PubSub for Components (assign_topic)

Livex aims to make it easier for components to subscribe to PubSub topics 
themselves, especially when the topic depends on the component's attrs or state.

assign_topic/4 works similarly to assign_new/3, subscribing the component to a 
PubSub topic. The topic name can be dynamically generated based on dependencies. 
If those dependencies change, the component would be re-subscribed to the new 
topic.

```elixir
defmodule MyAppWeb.Components.RealtimeDocumentStatus do
  use MyAppWeb, :livex_component

  attr :document_id, :uuid, required: true
  state :status_message, :string

  def pre_render(socket) do
    {:noreply,
     socket
     # Set initial status
     |> assign_new(:status_message, fn -> "Connecting..." end)
     # Subscribe to topic based on attr
     |> assign_topic(:doc_status_updates, [:document_id], fn assigns ->
       # Dynamically generate topic based on document_id
       "document_updates:#{assigns.document_id}"
     end)}
  end

  # This will be called when a message is published to the subscribed topic
  def handle_info({:doc_status_updates, %{message: msg}}, socket) do
    # Update component state based on the PubSub message
    {:noreply, assign(socket, :status_message, msg)}
  end

  def render(assigns) do
    ~H"""
    <div class="status-badge">
      Document <%= @document_id %>: <%= @status_message %>
    </div>
    """
  end
end
```
## Summary

By combining these features, Livex aims to provide:

- A cleaner conceptual model for LiveView and LiveComponent state and lifecycle.
- Reduced boilerplate for common patterns like URL state management, derived 
  data, and component communication.
- More declarative data flow, where changes to state or attrs automatically 
  propagate to derived data and streams via pre_render and dependency-aware 
  functions like assign_new and stream_new.
- Avoidance of many manual push_patch calls, as state changes naturally lead to 
  re-renders.

## Contributing

Contributions are welcome! This is an experimental project, so feel free to open
issues or submit pull requests with ideas or improvements.

## License

This project is licensed under the MIT License - see the LICENSE file for
details.

## Setup Instructions

1. Add Livex to your dependencies

Add livex to your dependencies in mix.exs:

```elixir
def deps do
  [
    {:livex, "~> 0.1.0"}
  ]
end
```
2. Configure your web module

Update your web module (typically lib/my_app_web.ex) to include Livex view and 
component definitions. This usually involves defining livex_view/0 and 
livex_component/0 functions that use Livex.LivexView or Livex.LivexComponent 
respectively, along with Livex.JSX and any shared HTML helpers.

Example lib/my_app_web.ex:

```elixir
defmodule MyAppWeb do
  # ... other functions like static_paths, router, channel, controller ...

  def livex_view do
    quote do
      use Phoenix.LiveView,
        layout: {MyAppWeb.Layouts, :app} # Or your desired layout

      unquote(view_helpers()) # Keep your existing view_helpers

      # Livex specific uses
      use Livex.LivexView
      use Livex.JSX # For JSX.emit, JSX.assign_data etc.
    end
  end

  def livex_component do
    quote do
      use Phoenix.LiveComponent

      # Livex specific uses
      use Livex.LivexComponent
      use Livex.JSX # For JSX.emit, JSX.assign_data etc.
    end
  end

  def view_helpers do
    quote do
      use Phoenix.HTML
      import Phoenix.LiveView.Helpers
      import Phoenix.View
      # ... other helpers like ErrorHelpers, Gettext, Routes, CoreComponents
      # import MyAppWeb.CoreComponents # If you have them
    end
  end

  # ... (rest of your web module, e.g., verified_routes)
end
```
3. JavaScript Integration

Ensure your esbuild configuration in config/config.exs includes the NODE_PATH to 
deps:

```elixir
config :esbuild,
  version: "0.17.11", # or your version
  my_app: [ # Replace my_app with your app name
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]
```

Add these two lines to your assets/js/app.js file:

```javascript
// Add this import near your other imports (after LiveSocket import)
import { enhanceLiveSocket } from "livex";

// Add this line after creating your LiveSocket instance but before connecting
// Example:
// let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
// let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}})
liveSocket = enhanceLiveSocket(liveSocket); // Add this line
// liveSocket.connect()
```
4. Using Livex in your application

Create LiveView modules using the new livex_view definition from your web module:

```elixir
defmodule MyAppWeb.MyPageView do
  use MyAppWeb, :livex_view # Assuming :livex_view is defined in MyAppWeb

  state :item_id, :string, url?: true
  state :is_editing_mode, :boolean

  # Your view code...
end
```

Create LiveComponents using the new livex_component definition:

```elixir
defmodule MyAppWeb.MyItemComponent do
  use MyAppWeb, :livex_component # Assuming :livex_component is defined in MyAppWeb

  attr :item_name, :string, required: true
  state :show_details, :boolean

  # Your component code...
end
```

```
