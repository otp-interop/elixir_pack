defmodule ElixirPackTest do
  use ExUnit.Case
  doctest ElixirPack

  test "greets the world" do
    assert ElixirPack.hello() == :world
  end
end
