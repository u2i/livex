# Livex

**This is not production code. It's a (fully functional) DX experiment to be able
to experiment with the combination of various features. But uses elixir trickery
and rather too much knowledge of liveview internals to make it work. Ideally the
end state is either for the features to be added to liveview, or for the
capability to add the features to be added.**

Livex is a library that provides type-safe LiveView components and views with URL
state management. It's an opinionated approach to solving common LiveView
development challenges.

## Why Livex?

LiveView is from my perspective the best available web development platform for
most tasks. The lack of the split brain of SPAs, and the integration with PubSub
makes it a joy to use.

However, there are some things that have been nagging me as I write coding
standards that I expect my LLM to follow:

- The most natural way to write liveview reducers isn't good practice for
  building a robust system - writing reducers as operations on socket with
  assigns is a really ergonomic way to alter state based on events. But if we
  want our apps to be resilient we should store our state in the url. And
  practically speaking while it's easy to alter a single assign, but it's rather
  more gnarly to alter a single query arg.
- Managing LiveComponent state in a robust way gets even more complicated. We
  need to delegate all state management to the parent, and deal with merging the
  parent's state concerns with all of the children to build the query string.
- Management of component state is hard work and there isn't a clear pattern for
  how to manage the various sorts of state (parent owned state, child owned
  state, state that requires persistence and state that can be regenerated).
- Closely related is how to message state transitions that relate to parent/child
  owned state, that's also a bit fuzzy.
- Refreshing externally stored state based on query string or component args is
  more naturally written in an event driven way (we got a new foo id in params,
  better refresh the bars) than a declarative way.
- It's cumbersome to build components that are self sufficient in terms of real
  time messaging.

These are all things that other component frameworks have solved for, so I
wondered if it would be possible to get all of these things into liveview, and
whether it would improve the developer experience if we did.

So this is an attempt to do that. Generally I've tried to design it in a way that
draws good conceptual ideas from other frameworks, but tried to do it in a way
that fits with and improves on LiveView rather than going in a dramatically
different direction. I will use React as a reference point however, as many of
these concepts are handled well there.

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

To see Livex in action, check out the demo application in the `../livex_demo`
directory which showcases all the features described below.

## Features

### Automatic State Management

The first thing that LivexView does is automatic state management. The way you do
this is in either a view or a component you add `state <param name>, <type>`,
with an optional `url?` parameter. This indicates that the framework should
automatically store this value in the client and automatically handle casting it
back to the proper type and putting in assigns. The `url?` parameter dictates
whether it's present in the url (and therefore will survive a page refresh and be
present when using 'back') or whether it's only used when the client tries to
reconnect (and so will survive a reconnect but not a refresh).

Example:

```elixir
defmodule MyApp.SomeView do
  use Livex.LivexView

  state :location_id, :uuid, url?: true
  state :name_filter, :string, url?: true
  state :show_dialog, :boolean

  # rest of your view code...
end
```

In this example, `location_id` and `name_filter` will be present in the URL,
while `show_dialog` will only be present on the client.

In React terms, this corresponds to state - that is state that is owned by the
component and is manipulated by reducers within that component.

This also works for live components. For example, if you have a form widget with
state that's not stored in an input:

```elixir
defmodule MyApp.FormComponent do
  use Livex.LivexComponent

  state :is_expanded, :boolean
  state :selected_tab, :string, url?: true

  # rest of your component code...
end
```

### Cleaning up State Management and View/Component Lifecycle

In React, the universe is divided into 'props' (state that is controlled by the
parent of a component) and 'state' (the internal state of a component).

We already have a clean concept of props in LiveView, we see it in functional
component 'attrs'. These are properties that are fully controlled by the parent.
So in that spirit, Livex uses `attr` for these properties.

The conceptual model of this kind of framework is basically: render -> event ->
reducer -> render -> event -> reducer, repeated ad infinitum. The reducers are
`handle_event`, `handle_info` and `handle_async`. But what we're missing in
current views and components is a place to declaratively describe the mapping
from props/attrs to the rendered view such that this can include updating of
derived state.

In React, `useMemo()` does this in the main component function, but this is
implemented using some non-functional magic. We could do that, but I opted not to
and instead introduced a `pre_render` function. With the addition of a variant of
`assigns_new` that, like `useMemo`, depends on other fields, we can largely
obviate the need for `mount`, `update` and `handle_params`. For example:

```elixir
defmodule MyApp.LocationView do
  use Livex.LivexView

  state :location_id, :string, url?: true

  def pre_render(socket) do
    {:noreply,
     assign_new(socket, :location, [:location_id], fn assigns ->
       MyApp.Domain.get_location!(assigns.location_id)
     end)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1><%= @location.name %></h1>
      <!-- rest of your template -->
    </div>
    """
  end
end
```

This will automatically pull in the correct location if `location_id` changes,
without needing to handle this in `mount` or `handle_params`.

### Events

We already have events in views/components - the `phx-<events>` that HTML
elements can have. Livex adds custom events that follow this same pattern. For
example, a modal component can have a `phx-close` event:

```elixir
defmodule MyApp.ModalComponent do
  use Livex.LivexComponent

  def render(assigns) do
    ~H"""
    <div class="modal">
      <div class="modal-content">
        <%= render_slot(@inner_block) %>
        <button phx-click={JSX.emit(:close)}>Cancel</button>
      </div>
    </div>
    """
  end

  # Handle the close event
  def handle_event("close", _, socket) do
    {:noreply, socket |> push_emit(:close)}
  end
end
```

Then in the parent component:

```elixir
<.live_component module={MyApp.ModalComponent} id="my-modal"
                 phx-close={JS.hide(to: "#my-modal")}>
  Modal content here
</.live_component>
```

To support closing the window from a server event, we can also do
`push_emit(socket, :close)`. The current implementation doesn't quite manage this
(because it does some macro magic to get the syntax I wanted) but a real
implementation in LiveView could handle propagating events from functional
components through any number of live components.

### Enable PubSub for Components

**This is not implemented yet**

LiveView has a great tool in PubSub that can solve a lot of the more complicated
state management and communication problems. Need to have two sibling components
talk to each other? Send a PubSub message.

The main limitation from the perspective of having self-contained components is
that components can't subscribe themselves to topics. Livex approaches this in a
similar way to the updated `assign_new`:

```elixir
defmodule MyApp.LocationComponent do
  use Livex.LivexComponent

  attr :location_id, :string, required: true

  def pre_render(socket) do
    {:noreply,
     socket
     |> assign_topic(:location_updates, [:location_id], fn assigns ->
       "locations:#{assigns.location_id}"
     end)}
  end

  # This will be called when a message is published to the topic
  def handle_info({:location_updates, location}, socket) do
    {:noreply, assign(socket, :location, location)}
  end
end
```

## Summary

Put this together and we can get both a conceptually cleaner component structure
that better splits operations into `pre_render`+`render` and reducers
(`handle_event`, `handle_async`, `handle_info`) and largely avoid the need for
`mount`, `handle_params` and `update`. We also avoid most uses of `push_patch`
because most intra-LiveView navigation is handled by updating state.

## Contributing

Contributions are welcome! This is an experimental project, so feel free to open
issues or submit pull requests with ideas or improvements.

## License

This project is licensed under the MIT License - see the LICENSE file for
details.

## Setup Instructions

### 1. Add Livex to your dependencies

Add livex to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:livex, "~> 0.1.0"}
  ]
end
```

### 2. Configure your web module

Update your web module (typically `lib/your_app_web.ex`) to include Livex view and component definitions:

```elixir
# Add these two new functions to your web module:

def livex_view do
  quote do
    use Livex.LivexView
    use Livex.JSX

    # Include your existing HTML helpers
    unquote(html_helpers())
  end
end

def livex_component do
  quote do
    use Livex.LivexComponent
    use Livex.JSX

    # Include your existing HTML helpers
    unquote(html_helpers())
  end
end
```

### 3. JavaScript Integration

Ensure your esbuild configuration in `config/config.exs` includes the NODE_PATH to deps:

```elixir
config :esbuild,
  version: "0.17.11",
  your_app: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]
```

Add these two lines to your `assets/js/app.js` file:

```javascript
// Add this import near your other imports (after LiveSocket import)
import { enhanceLiveSocket } from "livex";

// Add this line after creating your LiveSocket instance but before connecting
liveSocket = enhanceLiveSocket(liveSocket);
```

### 4. Using Livex in your application

Create LiveView modules using the new `livex_view` definition:

```elixir
defmodule MyAppWeb.SomeView do
  use MyAppWeb, :livex_view
  
  state :counter, :integer, url?: true
  state :show_modal, :boolean
  
  # Your view code...
end
```

Create LiveComponents using the new `livex_component` definition:

```elixir
defmodule MyAppWeb.SomeComponent do
  use MyAppWeb, :livex_component
  
  attr :title, :string, required: true
  state :is_expanded, :boolean
  
  # Your component code...
end
```
