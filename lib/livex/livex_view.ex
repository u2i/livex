defmodule Livex.LivexView do
  @moduledoc """
  Provides common LiveView functionality for typesafe LiveViews.

  This module is designed to be used with Phoenix LiveView and provides
  hooks and utilities for managing URL state in a type-safe manner.
  """

  defmodule Schema do
    @moduledoc """
    Injects the Livex DSL into your LiveView modules,
    and automatically generates a `changeset/2` based on
    declared `:attributes` and `:components`.
    """

    use Spark.Dsl,
      default_extensions: [
        extensions: [Livex.Schema.LivexViewDsl]
      ]
  end

  defmacro __using__(opts) do
    # Expand layout if possible to avoid compile-time dependencies
    opts =
      with true <- Keyword.keyword?(opts),
           {layout, template} <- Keyword.get(opts, :layout) do
        layout = Macro.expand(layout, %{__CALLER__ | function: {:__live__, 0}})
        Keyword.replace!(opts, :layout, {layout, template})
      else
        _ -> opts
      end

    quote bind_quoted: [opts: opts] do
      import Phoenix.LiveView
      @behaviour Phoenix.LiveView
      @before_compile Phoenix.LiveView.Renderer

      @phoenix_live_opts opts
      Module.register_attribute(__MODULE__, :phoenix_live_mount, accumulate: true)
      @before_compile Phoenix.LiveView

      # Phoenix.Component must come last so its @before_compile runs last
      use Phoenix.Component, Keyword.take(opts, [:global_prefixes])

      use Schema

      on_mount {__MODULE__, :default}

      def on_mount(:default, params, session, socket) do
        {:cont, socket} = __MODULE__.update_assigns_from_uri(params, session, socket)

        socket =
          socket
          |> Phoenix.LiveView.attach_hook(
            :update_uri,
            :after_render,
            &__MODULE__.update_uri_from_assigns/1
          )
          |> Phoenix.LiveView.attach_hook(
            :save_uri,
            :handle_params,
            &__MODULE__.update_assigns_from_uri/3
          )

        {:cont, socket}
      end

      @impl true
      def handle_event(event, %{"__target_path" => path_str} = params, socket) do
        __MODULE__.dispatch_component_event(event, params, socket)
      end
    end
  end
end
