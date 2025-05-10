defmodule Livex.PhoenixWeb.Layouts do
  use Phoenix.Component

  def app(assigns) do
    ~H"""
    <div class="app-layout">
      {@inner_content}
    </div>
    """
  end
end
