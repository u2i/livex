defmodule Livex.Utils do
  alias Livex.JSX
  alias Phoenix.LiveView.Socket
  alias Phoenix.Component

  def push_emit(%Socket{} = socket, event) do
    push_js(
      socket,
      JSX.build_push_op(
        Livex.JSX.get_target_from_assigns(socket.assigns),
        socket.assigns[String.to_existing_atom("phx-#{event}")],
        []
      )
    )
  end

  def push_js(%Socket{} = socket, %Phoenix.LiveView.JS{} = js) do
    Phoenix.LiveView.Utils.push_event(socket, "js-execute", %{
      ops: Phoenix.json_library().encode!(js.ops)
    })
  end

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
