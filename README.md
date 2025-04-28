# Livex

Livex is a library that provides type-safe LiveView components and views with URL state management.

## Installation

The package can be installed by adding `livex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:livex, "~> 0.1.0"}
  ]
end
```

## Features

- Type-safe LiveView components and views
- Automatic URL state management
- Form handling with validation
- Component state management

## Usage

### LivexView

```elixir
defmodule MyAppWeb.MyLiveView do
  use MyAppWeb, :livex_view

  attributes do
    attribute :count, :integer, default: 0
    attribute :name, :string, default: "Test"
    attribute :show_details, :boolean, default: false
  end

  components do
    has_one :modal, MyAppWeb.MyComponent
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("increment", _, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count + 1)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div>
      <h1>Hello, {@name}!</h1>
      <div>Count: {@count}</div>
      <button phx-click="increment">Increment</button>
    </div>
    """
  end
end
```

### LivexComponent

```elixir
defmodule MyAppWeb.MyComponent do
  use MyAppWeb, :livex_component

  attributes do
    attribute :item_id, :string
    attribute :live_action, :string
  end

  def mount(socket) do
    {:ok, initialize_private(socket)}
  end

  def update(assigns, socket) do
    socket = 
      socket
      |> assign(assigns)
      |> assign(:form_data, %{name: "Test Item"})
    
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div phx-target={@myself}>
      <h2>Edit Item {@item_id}</h2>
      <form phx-submit="save" phx-change="validate" phx-target={@myself}>
        <input type="text" name="name" value={@form_data.name} />
        <button type="submit">Save</button>
        <button type="button" phx-click="close_modal" phx-target={@myself}>Cancel</button>
      </form>
    </div>
    """
  end

  def handle_event("validate", %{"name" => name}, socket) do
    socket = 
      socket
      |> assign(:form_data, %{name: name})
      |> push_state()
    
    {:noreply, socket}
  end

  def handle_event("save", %{"name" => name}, socket) do
    {:noreply, push_delete(socket)}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_delete(socket)}
  end
end
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc).
