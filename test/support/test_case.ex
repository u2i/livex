defmodule Livex.TestCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.LiveViewTest
      import Mimic
    end
  end

  setup do
    Mimic.verify_on_exit!()
    %{conn: Phoenix.ConnTest.build_conn()}
  end
end
