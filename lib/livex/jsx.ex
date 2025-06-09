defmodule Livex.JSX do
  @moduledoc """
  Provides macros for client-side state updates and event emission in Livex components.

  This module contains two main sets of functionality:

  1. **JSX.emit** - Emit events from components to parent views/components
  2. **JSX.assign_state** - Update component state directly from templates

  ## Event Emission (JSX.emit)

  The `emit` macros allow components to emit events that can be handled by parent components
  or views. This creates a clean communication channel between child and parent components.

  ### Examples

  ```elixir
  # In a component template
  <button phx-click={JSX.emit(:close)}>Cancel</button>
  <button phx-click={JSX.emit(:save, value: %{id: @id, data: @form_data})}>Save</button>

  # In the parent component/view
  <.live_component 
    module={MyApp.ModalComponent} 
    id="my-modal" 
    phx-close="handle_modal_close"
    phx-save="handle_modal_save">
    Modal content here
  </.live_component>

  # In the parent's handle_event
  def handle_event("handle_modal_close", _, socket) do
    {:noreply, assign(socket, :modal_open, false)}
  end

  def handle_event("handle_modal_save", %{"id" => id, "data" => data}, socket) do
    # Process the saved data
    {:noreply, socket}
  end
  ```

  ## State Updates (JSX.assign_state)

  The `assign_state` macros allow updating component state directly from templates,
  without needing to write handle_event callbacks for simple state changes.

  ### Examples

  ```elixir
  # Update a single value
  <button phx-click={JSX.assign_state(:is_expanded, true)}>Expand</button>

  # Update multiple values at once
  <button phx-click={JSX.assign_state(is_expanded: false, selected_tab: "details")}>
    Close
  </button>

  # Conditional updates
  <button phx-click={
    if @is_expanded do
      JSX.assign_state(is_expanded: false, pending_value: @initial_value)
    else
      JSX.assign_state(is_expanded: true)
    end
  }>
    {if @is_expanded, do: "Close", else: "Expand"}
  </button>

  # Force a component refresh without changing state
  <button phx-click={JSX.assign_state()}>Refresh Component</button>
  ```

  ## Usage

  To use these macros, add `use Livex.JSX` to your module, or they are automatically
  imported when using `Livex.LivexView` or `Livex.LivexComponent`.
  """

  defmacro __using__(_opts \\ []) do
    quote do
      alias Livex.JSX
      require Livex.JSX
    end
  end

  alias Phoenix.LiveView.JS

  # --- Emit Macros ---

  @doc """
  Generates a JS command to emit a client-side event.

  ## Variants

  * `emit(js, event_suffix, opts)` - Chain on an existing JS struct with options
  * `emit(js, event_suffix)` - Chain on an existing JS struct without options
  * `emit(event_suffix, opts)` - Create a new JS chain with options
  * `emit(event_suffix)` - Create a new JS chain without options

  ## Parameters

  * `js` - An existing Phoenix.LiveView.JS struct to chain operations on
  * `event_suffix` - The suffix of the event to emit (e.g., "close" for "phx-close")
  * `opts` - Options for the event, such as `values: %{...}`

  ## Examples

  ```elixir
  # With existing JS chain and options
  JS.transition(...) |> JSX.emit("close", values: %{reason: "cancelled"})

  # With existing JS chain, no options
  JS.transition(...) |> JSX.emit("close")

  # New JS chain with options
  JSX.emit("close", values: %{reason: "cancelled"})

  # New JS chain without options
  JSX.emit("close")
  ```
  """

  defmacro emit(%Phoenix.LiveView.JS{} = js_ast, event_name_suffix_ast, opts_list_ast) do
    quote location: :keep do
      assigns_var = var!(assigns)
      event_name_suffix = unquote(event_name_suffix_ast)
      key_for_event_name = String.to_existing_atom("phx-#{event_name_suffix}")
      resolved_client_event = Map.fetch!(assigns_var, key_for_event_name)
      opts = unquote(opts_list_ast)
      resolved_target = Livex.JSX.get_target(assigns_var, opts)

      Livex.JSX.build_push_op(
        unquote(js_ast),
        resolved_target,
        resolved_client_event,
        opts
      )
    end
  end

  defmacro emit(%Phoenix.LiveView.JS{} = js_ast, event_name_suffix_ast) do
    quote location: :keep do
      assigns_var = var!(assigns)
      event_name_suffix = unquote(event_name_suffix_ast)
      key_for_event_name = String.to_existing_atom("phx-#{event_name_suffix}")
      resolved_client_event = Map.fetch!(assigns_var, key_for_event_name)
      resolved_target = Livex.JSX.get_target(assigns_var, [])

      Livex.JSX.build_push_op(
        unquote(js_ast),
        resolved_target,
        resolved_client_event,
        []
      )
    end
  end

  defmacro emit(event_name_suffix_ast, opts_list_ast) do
    quote location: :keep do
      assigns_var = var!(assigns)
      event_name_suffix = unquote(event_name_suffix_ast)
      key_for_event_name = String.to_existing_atom("phx-#{event_name_suffix}")
      resolved_client_event = Map.fetch!(assigns_var, key_for_event_name)
      opts = unquote(opts_list_ast)
      resolved_target = Livex.JSX.get_target(assigns_var, opts)

      Livex.JSX.build_push_op(
        %JS{},
        resolved_target,
        resolved_client_event,
        opts
      )
    end
  end

  defmacro emit(event_name_suffix_ast) do
    quote location: :keep do
      assigns_var = var!(assigns)
      event_name_suffix = unquote(event_name_suffix_ast)
      key_for_event_name = String.to_existing_atom("phx-#{event_name_suffix}")
      resolved_client_event = Map.fetch!(assigns_var, key_for_event_name)
      resolved_target = Livex.JSX.get_target(assigns_var, [])

      Livex.JSX.build_push_op(
        %JS{},
        resolved_target,
        resolved_client_event,
        []
      )
    end
  end

  # --- Core Helper Functions (Called by Macro-Generated Code) ---
  # These functions now take the pre-resolved `resolved_target`.

  @doc false
  def build_push_op(%Phoenix.LiveView.JS{} = js, resolved_target, client_event_name, opts_list) do
    value_map = Keyword.get(opts_list, :value, %{})

    # Handle the case where client_event_name is a JS object
    if is_struct(client_event_name, Phoenix.LiveView.JS) do
      # Find the __component_action push operation in the JS object and merge our options
      merge_with_component_action(client_event_name, resolved_target, value_map)
    else
      # Regular string event name
      JS.push(js, "#{client_event_name}",
        target: resolved_target,
        value: value_map
      )
    end
  end

  @doc false
  def build_push_op(%Phoenix.LiveView.JS{} = js, resolved_target, client_event_name) do
    build_push_op(js, resolved_target, client_event_name, [])
  end

  @doc false
  def build_push_op(resolved_target, client_event_name, opts_list) do
    build_push_op(%JS{}, resolved_target, client_event_name, opts_list)
  end

  @doc false
  def build_push_op(resolved_target, client_event_name) do
    build_push_op(%JS{}, resolved_target, client_event_name, [])
  end

  @doc false
  def merge_with_component_action(%Phoenix.LiveView.JS{ops: ops} = js, resolved_target, value_map) do
    # Find the __component_action push operation
    updated_ops =
      Enum.map(ops, fn
        %{kind: :push, event: "__component_action", args: args} = op ->
          # Merge our value_map with the existing value map
          updated_args =
            Map.update(args, :value, value_map, fn existing_value ->
              Map.merge(existing_value, value_map)
            end)

          # Update target if provided
          updated_args =
            if resolved_target,
              do: Map.put(updated_args, :target, resolved_target),
              else: updated_args

          %{op | args: updated_args}

        op ->
          op
      end)

    %{js | ops: updated_ops}
  end

  @doc false
  def get_target(assigns, opts_list) do
    case Keyword.get(opts_list, :to) do
      nil -> get_target_from_assigns(assigns)
      explicit_target -> explicit_target
    end
  end

  @doc false
  def get_target_from_assigns(%{"phx-target": %Phoenix.LiveComponent.CID{cid: cid_val}}),
    do: cid_val

  @doc false
  def get_target_from_assigns(_assigns), do: nil

  @doc """
  Creates a JS command to update component data from the client with a keyword list of options.

  This macro allows updating multiple component state values directly from client-side events.

  ## Parameters

  * `opts` - A keyword list of key-value pairs to update in the component's state

  ## Examples

  ```elixir
  <button phx-click={JSX.assign_state(is_expanded: true, selected_tab: "details")}>
    Expand Details
  </button>
  ```
  """
  defmacro assign_state(opts) when is_list(opts) do
    quote do
      Livex.JSX.do_assign_state(
        var!(assigns)[:myself],
        unquote(opts)
      )
    end
  end

  @doc """
  Creates a JS command to update a single component data value from the client.

  See `assign_state/1` for updating multiple values at once.

  ## Parameters

  * `key` - The key to update in the component's state
  * `val` - The value to assign

  ## Examples

  ```elixir
  <button phx-click={JSX.assign_state(:is_expanded, true)}>Expand</button>
  ```
  """
  defmacro assign_state(arg1, arg2) do
    quote do
      Livex.JSX.do_assign_state(
        var!(assigns)[:myself],
        unquote(arg1),
        unquote(arg2)
      )
    end
  end

  defmacro assign_state(js, key, val) do
    quote do
      Livex.JSX.do_assign_state(
        unquote(js),
        var!(assigns)[:myself],
        unquote(key),
        unquote(val)
      )
    end
  end

  @doc """
  Creates a JS command to trigger a component update without changing any data.

  This is useful for forcing a component to re-render.

  ## Examples

  ```elixir
  <button phx-click={JSX.assign_state()}>Refresh Component</button>
  ```
  """
  defmacro assign_state() do
    quote do
      Livex.JSX.do_assign_state(var!(assigns)[:myself])
    end
  end

  @doc false
  def do_assign_state(target, %Phoenix.LiveView.JS{} = js, opts) when is_list(opts) do
    # Convert keyword list to map for multiple key-value pairs
    value_map = Enum.into(opts, %{})

    JS.push(js, "__component_action",
      target: target,
      value: value_map
    )
  end

  @doc false
  def do_assign_state(target, key, value) do
    JS.push("__component_action",
      target: target,
      value: %{key => value}
    )
  end

  def do_assign_state(js, target, key, value) do
    JS.push(js, "__component_action",
      target: target,
      value: %{key => value}
    )
  end

  @doc false
  def do_assign_state(target, opts) when is_list(opts) do
    # Convert keyword list to map for multiple key-value pairs
    value_map = Enum.into(opts, %{})

    JS.push("__component_action",
      target: target,
      value: value_map
    )
  end

  @doc false
  def do_assign_state(target) do
    JS.push("__component_action", target: target)
  end
end
