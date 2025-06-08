defmodule Livex.Handlers do
  @moduledoc """
  Handlers for component events in Livex.

  This module contains functions for handling events that are dispatched to components.
  """

  alias Phoenix.Component

  @doc """
  Handles component events by mapping parameters and calling pre_render.

  This function is used internally by Livex to process events that are sent to components.

  ## Parameters

  * `module` - The component module
  * `params` - The event parameters
  * `socket` - The LiveView socket

  ## Returns

  * `{:noreply, socket}` - The updated socket after processing the event
  """
  def handle_component_event(module, params, socket) do
    mapped_params =
      Livex.ParamsMapper.map_params(
        module,
        params |> IO.inspect(label: :params)
      )

    socket = Component.assign(socket, mapped_params |> IO.inspect(label: :mapped_params))
    module.pre_render(socket)
  end
end
