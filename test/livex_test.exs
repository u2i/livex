defmodule LivexTest do
  use ExUnit.Case
  doctest Livex

  test "greets the world" do
    assert Livex.hello() == :world
  end
end
