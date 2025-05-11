defmodule Livex.JSX do
  @moduledoc """
  Provides macros for emitting client-side events from LiveViews/LiveComponents.

  This module allows components to emit events that can be handled by parent components
  or views. The client-side event name to be dispatched is looked up from assigns
  using a key derived from the provided event suffix (e.g., assigns[:"phx-suffix"]).

  ## Examples

  ```elixir
  # In a component template
  <button phx-click={JSX.emit(:close)}>Cancel</button>

  # In the parent component/view
  <.live_component module={MyApp.ModalComponent} id="my-modal" phx-close={JS.hide(to: "#my-modal")}>
    Modal content here
  </.live_component>
  ```

  To use the `emit` macro, call it as `Livex.JSX.emit(...)`.
  """

  defmacro __using__(_opts \\ []) do
    quote do
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
    JS.push(js, "#{client_event_name}",
      target: resolved_target,
      value: value_map
    )
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
  <button phx-click={JSX.assign_data(is_expanded: true, selected_tab: "details")}>
    Expand Details
  </button>
  ```
  """
  defmacro assign_data(opts) when is_list(opts) do
    quote do
      Livex.JSX.do_assign_data(
        var!(assigns)[:myself],
        unquote(opts)
      )
    end
  end

  @doc """
  Creates a JS command to update a single component data value from the client.

  See `assign_data/1` for updating multiple values at once.

  ## Parameters

  * `key` - The key to update in the component's state
  * `val` - The value to assign

  ## Examples

  ```elixir
  <button phx-click={JSX.assign_data(:is_expanded, true)}>Expand</button>
  ```
  """
  defmacro assign_data(key, val) do
    quote do
      Livex.JSX.do_assign_data(
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
  <button phx-click={JSX.assign_data()}>Refresh Component</button>
  ```
  """
  defmacro assign_data() do
    quote do
      Livex.JSX.do_assign_data(var!(assigns)[:myself])
    end
  end

  @doc false
  def do_assign_data(target, key, value) do
    JS.push("__component_action",
      target: target,
      value: %{key => value}
    )
  end

  @doc false
  def do_assign_data(target, opts) when is_list(opts) do
    # Convert keyword list to map for multiple key-value pairs
    value_map = Enum.into(opts, %{})

    JS.push("__component_action",
      target: target,
      value: value_map
    )
  end

  @doc false
  def do_assign_data(target) do
    JS.push("__component_action", target: target)
  end
end
