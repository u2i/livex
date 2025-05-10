defmodule Livex.Handlers do
  alias Phoenix.Component

  def handle_component_event(module, params, socket) do
    mapped_params =
      Livex.ParamsMapper.map_params(
        module,
        params
      )

    socket = Component.assign(socket, mapped_params)
    module.pre_render(socket)
  end
end
