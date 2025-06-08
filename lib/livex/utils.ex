defmodule Livex.Utils do
  @moduledoc """
  Utility functions for Livex components and views.

  This module provides helper functions for event handling, JavaScript execution,
  and state management with dependency tracking.
  """

  alias Livex.JSX
  alias Phoenix.LiveView.Socket
  alias Phoenix.Component

  @doc """
  Emits a client-side event from the server.

  This function allows components to emit events that can be handled by parent components
  or views, similar to how JSX.emit works but from server-side code.

  ## Parameters

  * `socket` - The LiveView socket
  * `event` - The event suffix (will be looked up in assigns as "phx-\#{event}")
  * `opts` - Options to pass to the event (default: [])

  ## Behavior

  * If the event value in assigns is a string, it will emit a regular event
  * If the event value is a JS struct (from JSX.assign_state), it will merge the value map
    into the existing JS operations, allowing you to combine state updates with event emission

  ## Examples

  ```elixir
  # Basic event emission
  def handle_event("close", _, socket) do
    {:noreply, socket |> push_emit(:on_close)}
  end

  # Event with value
  def handle_event("save", _, socket) do
    {:noreply, socket |> push_emit(:saved, value: %{id: socket.assigns.id})}
  end

  # Combined with state update (in parent template)
  <.live_component
    module={MyApp.FormComponent}
    id="my-form"
    phx-saved={JSX.assign_state(modal_open: false)}
  />
  ```
  """
  def push_emit(%Socket{} = socket, event, opts \\ []) do
    IO.inspect(event, label: "Original JS")
    IO.inspect(opts, label: "Options")

    case event do
      # If the event value is a JS struct, we need to merge the value map into the existing JS ops
      %Phoenix.LiveView.JS{} = js ->
        values = Keyword.get(opts, :values, %{})
        IO.inspect(values, label: "Values to merge")

        # Directly merge the values into the JS struct
        js_with_values = merge_value_into_js(js, values)
        IO.inspect(js_with_values, label: "After merge_value_into_js")

        # # Add target if needed
        # target = Livex.JSX.get_target_from_assigns(socket.assigns)
        # IO.inspect(target, label: "Target")
        #
        # js_with_target =
        #   if target,
        #     do: Phoenix.LiveView.JS.set_attribute(js_with_values, "data-target", target),
        #     else: js_with_values
        #
        IO.inspect(js_with_values, label: "After adding target")

        # Push the modified JS struct
        push_js(socket, js_with_values)

      # If the event value is a string, use the original behavior
      event when is_binary(event) ->
        push_js(
          socket,
          JSX.build_push_op(
            Livex.JSX.get_target_from_assigns(socket.assigns),
            event,
            opts
          )
        )
    end
  end

  # Helper function to merge a value map into a JS struct's operations
  defp merge_value_into_js(%Phoenix.LiveView.JS{ops: _ops} = js, value_map)
       when map_size(value_map) == 0 do
    # If there's no value map to merge, return the JS struct as is
    js
  end

  defp merge_value_into_js(%Phoenix.LiveView.JS{ops: ops} = js, value_map) do
    IO.inspect(ops, label: "Original ops")

    # The issue is that Phoenix.LiveView.JS.push is creating a new push operation
    # Instead of trying to modify the existing operations, let's create a new JS object
    # with just the value we want to add

    # Find if there's an existing push operation
    has_push =
      Enum.any?(ops, fn op ->
        is_list(op) && length(op) >= 2 && Enum.at(op, 0) == "push"
      end)

    if has_push do
      # Get the first push operation
      {push_op, index} =
        ops
        |> Enum.with_index()
        |> Enum.find(fn {op, _} ->
          is_list(op) && length(op) >= 2 && Enum.at(op, 0) == "push"
        end)

      # Extract the details from the push operation
      [_, details] = push_op

      # Update the details with our value
      updated_details = Map.put(details, "value", value_map)

      # Create a new push operation with the updated details
      updated_push_op = ["push", updated_details]

      # Replace the push operation in the ops list
      updated_ops = List.replace_at(ops, index, updated_push_op)

      # Return the updated JS struct
      %{js | ops: updated_ops}
    else
      # If there's no push operation, add a new one with the value map
      Phoenix.LiveView.JS.push(js, "", value: value_map)
    end
  end

  @doc """
  Pushes a JavaScript command to be executed on the client.

  ## Parameters

  * `socket` - The LiveView socket
  * `js` - The Phoenix.LiveView.JS struct containing operations to execute

  ## Returns

  * The updated socket
  """
  def push_js(%Socket{} = socket, %Phoenix.LiveView.JS{} = js, opts \\ []) do
    Phoenix.LiveView.Utils.push_event(socket, "js-execute", %{
      ops: Phoenix.json_library().encode!(js.ops),
      to: opts[:to]
    })
  end

  @doc """
  Assigns a new value to the socket if it doesn't exist or if any of its dependencies have changed.

  This function is similar to Phoenix.Component.assign_new/3, but with dependency tracking.
  It will recompute the value if any of the dependencies have changed in the socket's assigns.

  ## Parameters

  * `socket` - The LiveView socket
  * `key` - The key to assign the value to
  * `deps` - A list of keys that this value depends on
  * `fun` - A function that returns the value to assign

  ## Examples

  ```elixir
  def pre_render(socket) do
    {:noreply,
     assign_new(socket, :location, [:location_id], fn assigns -> 
       MyApp.Domain.get_location!(assigns.location_id)
     end)}
  end
  ```
  """
  def assign_new(%Socket{} = socket, key, deps, fun) do
    {changed, socket} = deps_in_changed?(socket, deps)

    if changed do
      case fun do
        fun when is_function(fun, 1) -> Component.assign(socket, key, fun.(socket.assigns))
        fun when is_function(fun, 0) -> Component.assign(socket, key, fun.())
      end
    else
      Component.assign_new(socket, key, fun)
    end
  end

  defp deps_in_changed?(socket, deps) do
    Enum.reduce(deps, {false, socket}, fn dep, {changed, acc_socket} ->
      if changed do
        {true, acc_socket}
      else
        case dep do
          atom when is_atom(atom) ->
            {Map.has_key?(socket.assigns.__changed__, atom), acc_socket}

          fun when is_function(fun, 1) ->
            # Calculate the new value
            new_value = fun.(socket.assigns)

            # Get the stored values map or initialize it
            stored_values = Map.get(acc_socket.private, :deps_calculated_values, %{})

            # Generate a unique key for this function
            fun_key = :erlang.fun_info(fun)[:unique]

            # Get the previously stored value for this function
            prev_value = Map.get(stored_values, fun_key)

            # Check if the value has changed
            value_changed = prev_value != new_value

            # Store the new value for future comparisons
            updated_socket =
              if value_changed do
                updated_values = Map.put(stored_values, fun_key, new_value)
                private = Map.put(acc_socket.private, :deps_calculated_values, updated_values)
                Map.put(acc_socket, :private, private)
              else
                acc_socket
              end

            {value_changed, updated_socket}

          _ ->
            raise ArgumentError,
                  "Dependencies must be atoms or functions that take assigns as argument"
        end
      end
    end)
  end

  def stream_new(socket, key, deps, fun) do
    unless Map.has_key?(socket.assigns, :streams) &&
             Map.has_key?(socket.assigns.streams, key) &&
             Map.has_key?(socket.assigns.streams, :__changed__) &&
             MapSet.disjoint?(socket.assigns.streams.__changed__, MapSet.new(deps)) do
      Phoenix.LiveView.stream(socket, key, fun.(socket.assigns), reset: true)
    else
      socket
    end
  end

  def send_message(module, socket, event, payload) do
    case target = socket.assigns.target do
      nil ->
        send(self(), %{__dispatch_message: event, source_module: module, payload: payload})
        socket

      _ ->
        {:ok, socket} =
          Phoenix.LiveView.send_update(socket, target, %{
            __dispatch_message: event,
            source_module: module,
            payload: payload
          })

        socket
    end
  end

  def subscribe(socket, key, deps, topic_fun) do
    socket =
      if !Map.has_key?(socket.private, :subscriptions) do
        private = Map.put(socket.private, :subscriptions, %{})
        Map.put(socket, :private, private)
      else
        socket
      end

    fun_res = topic_fun.(socket.assigns)

    cond do
      !Map.has_key?(socket.private.subscriptions, key) ->
        private = put_in(socket.private, [:subscriptions, key], fun_res)
        send(self(), {:__register_topic, socket.assigns.myself, topic_fun.(socket.assigns)})
        Map.put(socket, :private, private)

      deps_in_changed?(socket, deps) && get_in(socket.private.subscriptions[key]) != fun_res ->
        # TODO: unsubscribe old one
        send(self(), {:__register_topic, socket.assigns.myself, topic_fun.(socket.assigns)})
        socket

      true ->
        socket
    end
  end
end
