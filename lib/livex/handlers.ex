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
        params
      )

    socket = Component.assign(socket, mapped_params)
    module.pre_render(socket)
  end

  def handle_event(module, event, %{"__module" => component} = params, socket) do
    params =
      component
      |> String.to_existing_atom()
      |> Spark.Dsl.Extension.get_entities([:attributes])
      |> Enum.filter(&match?(%Livex.Schema.Event{}, &1))
      |> Enum.filter(fn x -> String.to_existing_atom(event) == x.name end)
      |> Enum.reduce(%{}, fn item, acc ->
        item.values
        |> Enum.reduce(acc, fn i, acc ->
          if Map.has_key?(params, "#{i.name}") do
            Map.put(acc, i.name, Livex.ParamsMapper.cast(params["#{i.name}"], i.type))
          else
            acc
          end
        end)

        # IO.inspect(item)
      end)

    module.handle_event(
      component |> String.to_existing_atom(),
      event |> String.to_existing_atom(),
      params,
      socket
    )
  end
end
