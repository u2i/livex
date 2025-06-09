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

  @doc """
  Asynchronously assigns multiple values to the socket with dependency tracking.

  This function allows you to perform multiple async operations with dependencies
  between them. Operations will be executed in parallel when possible, but will respect
  the dependency order.

  ## Parameters

  * `socket` - The LiveView socket
  * `assignments` - A list of assignment specifications, each being a tuple of:
    * `key` - The key to assign the value to
    * `deps` - A list of keys that this value depends on (can include other keys being assigned)
    * `fun` - A function that returns `{:ok, value}` or `{:error, reason}`

  ## Examples

  ```elixir
  def mount(_params, _session, socket) do
    {:ok,
     assign_async_new(socket, [
       # These two will run in parallel
       {:location, [:location_id], fn ->
         case MyApp.Domain.get_location(socket.assigns.location_id) do
           {:ok, location} -> {:ok, location}
           {:error, reason} -> {:error, reason}
         end
       end},
       
       {:user, [:user_id], fn ->
         case MyApp.Accounts.get_user(socket.assigns.user_id) do
           {:ok, user} -> {:ok, user}
           {:error, reason} -> {:error, reason}
         end
       end},
       
       # This will run after both location and user are assigned
       {:permissions, [:user, :location], fn ->
         # These values will be available in the assigns when this function runs
         user = socket.assigns.user.result
         location = socket.assigns.location.result
         
         case MyApp.Permissions.get_permissions(user, location) do
           {:ok, permissions} -> {:ok, permissions}
           {:error, reason} -> {:error, reason}
         end
       end}
     ])}
  end
  ```

  ## Handling Results

  Each assigned key will contain an `%AsyncResult{}` struct that you can pattern match on in your templates:

  ```heex
  <.async_result :let={location} assign={@location}>
    <:loading>Loading location...</:loading>
    <:failed :let={reason}>Failed to load location: <%= inspect(reason) %></:failed>
    <div>Location: <%= location.name %></div>
  </.async_result>
  ```
  """
  def assign_async_new(%Socket{} = socket, assignments, caller) when is_list(assignments) do
    # Extract all keys
    all_keys = Enum.map(assignments, fn {key, _deps, _fun} -> key end)

    # Create a dependency graph
    dependency_graph = build_dependency_graph(assignments)

    # Create a function that will execute all assignments in the correct order
    async_fun = fn ->
      # Create an agent to store intermediate results
      {:ok, agent} = Agent.start_link(fn -> %{} end)

      try do
        # Execute assignments in topological order
        execute_assignments_in_order(assignments, dependency_graph, agent)

        # Get all results
        results = Agent.get(agent, & &1)

        # Check if any result is an error
        if Enum.any?(results, fn {_key, result} ->
             match?({:error, _}, result) || match?({:exit, _}, result)
           end) do
          # Return the first error
          {_key, error} =
            Enum.find(results, fn {_key, result} ->
              match?({:error, _}, result) || match?({:exit, _}, result)
            end)

          error
        else
          # Create a map of successful results
          result_map =
            results
            |> Enum.map(fn {key, {:ok, value}} -> {key, value} end)
            |> Map.new()

          {:ok, result_map}
        end
      after
        Agent.stop(agent)
      end
    end

    # Use Phoenix.LiveView.assign_async to execute the function
    Phoenix.LiveView.Async.assign_async(socket, all_keys, async_fun, caller)
  end

  @doc """
  Executes a list of assignments in dependency order and returns the results.
  
  This function is used by the `assign_async_new` macro to execute assignments
  in the correct order based on their dependencies.
  
  ## Parameters
  
  * `assignments` - A list of assignment specifications, each being a tuple of:
    * `key` - The key to assign the value to
    * `deps` - A list of keys that this value depends on
    * `fun` - A function that returns `{:ok, value}` or `{:error, reason}`
  
  ## Returns
  
  * `{:ok, map}` - A map of successful results
  * `{:error, reason}` - An error reason
  """
  def execute_async_assignments(assignments) when is_list(assignments) do
    IO.puts("execute_async_assignments called with #{length(assignments)} assignments")
    IO.inspect(assignments, label: "Assignments")
    
    # Create a dependency graph
    dependency_graph = build_dependency_graph(assignments)
    IO.inspect(dependency_graph, label: "Dependency graph")
    
    # Create an agent to store intermediate results
    {:ok, agent} = Agent.start_link(fn -> %{} end)
    
    try do
      # Execute assignments in topological order
      execute_assignments_in_order(assignments, dependency_graph, agent)
      
      # Get all results
      results = Agent.get(agent, & &1)
      IO.inspect(results, label: "Results from agent")
      
      # Check if any result is an error
      if Enum.any?(results, fn {_key, result} ->
           match?({:error, _}, result) || match?({:exit, _}, result)
         end) do
        # Return the first error
        {_key, error} =
          Enum.find(results, fn {_key, result} ->
            match?({:error, _}, result) || match?({:exit, _}, result)
          end)
        
        IO.puts("Error found: #{inspect(error)}")
        error
      else
        # Create a map of successful results
        result_map =
          results
          |> Enum.map(fn {key, {:ok, value}} -> {key, value} end)
          |> Map.new()
        
        IO.puts("Success! Result map: #{inspect(result_map)}")
        {:ok, result_map}
      end
    after
      Agent.stop(agent)
    end
  end
  
  # Execute assignments in topological order
  defp execute_assignments_in_order(assignments, dependency_graph, agent) do
    # Find the execution order based on dependencies
    execution_order = topological_sort(dependency_graph)
    IO.puts("Execution order: #{inspect(execution_order)}")

    # Execute each assignment in order
    Enum.each(execution_order, fn key ->
      IO.puts("Executing assignment for key: #{inspect(key)}")
      
      # Find the assignment spec
      assignment_spec = Enum.find(assignments, fn {k, _, _} -> k == key end)
      IO.inspect(assignment_spec, label: "Assignment spec for #{inspect(key)}")
      
      {_key, deps, fun} = assignment_spec

      # Get the values of dependencies that are other assignments
      dep_values =
        deps
        |> Enum.filter(fn dep -> Enum.any?(assignments, fn {k, _, _} -> k == dep end) end)
        |> Enum.map(fn dep ->
          case Agent.get(agent, fn state -> Map.get(state, dep) end) do
            {:ok, value} -> {dep, value}
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Map.new()
      
      IO.inspect(dep_values, label: "Dependency values for #{inspect(key)}")
      IO.inspect(fun, label: "Function for #{inspect(key)}")

      # Execute the function
      result =
        try do
          IO.puts("Calling function for #{inspect(key)}")
          fun_result = fun.(dep_values)
          IO.inspect(fun_result, label: "Function result for #{inspect(key)}")
          fun_result
        catch
          kind, reason -> 
            IO.puts("Error calling function for #{inspect(key)}: #{inspect(kind)}, #{inspect(reason)}")
            {:exit, {kind, reason, __STACKTRACE__}}
        end

      # Store the result
      IO.puts("Storing result for #{inspect(key)}: #{inspect(result)}")
      Agent.update(agent, fn state -> Map.put(state, key, result) end)
    end)
  end

  # Build a dependency graph from the assignments
  defp build_dependency_graph(assignments) do
    Enum.reduce(assignments, %{}, fn {key, deps, _fun}, graph ->
      # Add this node to the graph if it doesn't exist
      graph = Map.put_new(graph, key, [])

      # Add edges for each dependency
      Enum.reduce(deps, graph, fn dep, acc_graph ->
        # Only add dependencies that are keys in our assignments
        if Enum.any?(assignments, fn {k, _, _} -> k == dep end) do
          # Add this key as a dependent of the dependency
          Map.update(acc_graph, dep, [key], fn dependents -> [key | dependents] end)
        else
          acc_graph
        end
      end)
    end)
  end

  # Perform a topological sort to determine execution order
  defp topological_sort(graph) do
    {sorted, _} = do_topological_sort(graph, [], MapSet.new())
    Enum.reverse(sorted)
  end

  defp do_topological_sort(graph, sorted, visited) do
    # Find nodes with no dependencies (no incoming edges)
    roots =
      graph
      |> Map.keys()
      |> Enum.filter(fn node ->
        not Enum.any?(graph, fn {_, deps} -> node in deps end) and
          not MapSet.member?(visited, node)
      end)

    if Enum.empty?(roots) do
      # If there are no roots but we still have unvisited nodes, there's a cycle
      if Enum.any?(graph, fn {node, _} -> not MapSet.member?(visited, node) end) do
        remaining = Enum.filter(Map.keys(graph), fn node -> not MapSet.member?(visited, node) end)
        raise "Circular dependency detected in assign_async_new: #{inspect(remaining)}"
      end

      {sorted, visited}
    else
      # Visit each root
      Enum.reduce(roots, {sorted, visited}, fn root, {acc_sorted, acc_visited} ->
        # Mark this node as visited
        new_visited = MapSet.put(acc_visited, root)

        # Remove this node from the graph
        new_graph = Map.delete(graph, root)

        # Recursively visit its dependents
        {new_sorted, new_visited} =
          do_topological_sort(new_graph, [root | acc_sorted], new_visited)

        {new_sorted, new_visited}
      end)
    end
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
