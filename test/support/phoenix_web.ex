defmodule Livex.PhoenixWeb do
  def livex_view do
    quote do
      use Phoenix.LiveView
      use Livex.LivexView, layout: {Livex.PhoenixWeb.Layouts, :app}
    end
  end

  def livex_component do
    quote do
      use Livex.LivexComponent
    end
  end
end
