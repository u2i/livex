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

  ## Examples

  ```elixir
  def handle_event("close", _, socket) do
    {:noreply, socket |> push_emit(:close)}
  end
  ```
  """
  def push_emit(%Socket{} = socket, event, opts \\ []) do
    push_js(
      socket,
      JSX.build_push_op(
        Livex.JSX.get_target_from_assigns(socket.assigns),
        socket.assigns[String.to_existing_atom("phx-#{event}")],
        opts
      )
    )
  end

  @doc """
  Pushes a JavaScript command to be executed on the client.

  ## Parameters

  * `socket` - The LiveView socket
  * `js` - The Phoenix.LiveView.JS struct containing operations to execute

  ## Returns

  * The updated socket
  """
  def push_js(%Socket{} = socket, %Phoenix.LiveView.JS{} = js) do
    Phoenix.LiveView.Utils.push_event(socket, "js-execute", %{
      ops: Phoenix.json_library().encode!(js.ops)
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
    if deps_in_changed?(socket, deps) do
      case fun do
        fun when is_function(fun, 1) -> Component.assign(socket, key, fun.(socket.assigns))
        fun when is_function(fun, 0) -> Component.assign(socket, key, fun.())
      end
    else
      Component.assign_new(socket, key, fun)
    end
  end

  defp deps_in_changed?(socket, deps) do
    Enum.any?(deps, &Map.has_key?(socket.assigns.__changed__, &1))
  end
end
