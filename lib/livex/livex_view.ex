defmodule Livex.LivexView do
  defmodule Schema do
    use Spark.Dsl,
      default_extensions: [
        extensions: [Livex.Schema.LivexViewDsl]
      ]
  end

  defmacro __using__(_opts) do
    quote do
      use Phoenix.LiveView
      use Schema

      defdelegate push_js(socket, event), to: Livex.Utils
      defdelegate assign_new(socket, key, deps, fun), to: Livex.Utils

      def handle_info({:__dispatch_event, fun, data}, socket) do
        fun.(data, socket)
      end

      @impl true
      def handle_event("__component_action", params, socket) do
        Livex.Handlers.handle_component_event(
          __MODULE__,
          params,
          socket
        )
      end

      def stream_new(socket, key, fun) do
        if Map.has_key?(socket.assigns.__changed__, key) do
          assign(socket, key, fun.())
        else
          socket
        end
      end

      on_mount {__MODULE__, :__livex}

      def on_mount(:__livex, params, session, socket) do
        Livex.LivexView.on_mount(__MODULE__, params, session, socket)
      end

      @before_compile unquote(__MODULE__)
    end
  end

  # This runs *after* the module has compiled all its own defs.
  defmacro __before_compile__(_env) do
    quote do
      defoverridable render: 1

      def render(assigns) do
        super(assigns) |> Livex.RenderedManipulator.wrap_in_div(__MODULE__, assigns)
      end

      defoverridable handle_event: 3

      def handle_event(event, params, socket) do
        case super(event, params, socket) do
          {:noreply, socket} ->
            pre_render(socket)

          {:reply, msg, socket} ->
            {:noreply, socket} = pre_render(socket)
            {:reply, msg, socket}
        end
      end

      defoverridable handle_params: 3

      def handle_params(params, uri, socket) do
        {:noreply, socket} = super(params, uri, socket)
        pre_render(socket)
      end

      defoverridable handle_info: 2

      def handle_info(msg, socket) do
        case super(msg, socket) do
          {:noreply, socket} ->
            pre_render(socket)

          {:reply, msg, socket} ->
            {:noreply, socket} = pre_render(socket)
            {:reply, msg, socket}
        end
      end
    end
  end

  alias Livex.ParamsMapper
  alias Phoenix.Component

  def assign_from_uri(module, params, uri, socket) when is_atom(module) and is_map(params) do
    socket
    |> Component.assign(:uri, uri)
    |> Component.assign(ParamsMapper.map_params(module, params))
    |> then(&{:cont, &1})
  end

  def on_mount(module, params, _session, socket) do
    {:cont, socket} = Livex.LivexView.assign_from_uri(module, params, nil, socket)

    socket =
      socket
      |> Phoenix.LiveView.attach_hook(
        :set_params,
        :handle_params,
        fn params, uri, socket ->
          Process.put(:__current_params, params)

          %URI{path: current_path, host: host} = URI.parse(uri)

          %{route: pattern} =
            Phoenix.Router.route_info(socket.router, "GET", current_path, host)

          Process.put(:__current_route, pattern)
          {:cont, socket}
        end
      )
      |> Phoenix.LiveView.attach_hook(
        :save_uri,
        :handle_params,
        fn params, uri, socket ->
          Livex.LivexView.assign_from_uri(module, params, uri, socket)
        end
      )
      |> Phoenix.LiveView.attach_hook(
        :clear_params,
        :after_render,
        fn socket ->
          Process.put(:__current_params, nil)
          socket
        end
      )

    {:cont, socket}
  end
end
